# Claim C3: causal quorum completion bound (docs/CAUSAL_QUORUM_BOUND.md).
#
# The closed-form reference below is independent of both the engine transport
# (`light_cone_intersection`) and the oracle's bisection solver: for 1-D
# constant-velocity motion the null condition c (t - t_e) = |x0 + v t - x_e| is
# linear in t on each side of the emitter, so the arrival time is explicit.

const _C3 = RelativisticDistributedSystemsSim.Research

"""
Closed-form earliest null arrival from emitter event (t_e, x_e) on the 1-D
inertial receiver x(t) = x0 + v t. With D = x0 + v t_e - x_e (receiver offset
at emission), the receiver stays on the same side of x_e until reception
(|v| < c), so c (t - t_e) = sign(D) (D + v (t - t_e)), giving
t = t_e + |D| / (c - sign(D) v).
"""
function closed_form_arrival(c, t_e, x_e, x0, v)
    D = x0 + v * t_e - x_e
    D == 0 && return t_e
    return t_e + abs(D) / (c - sign(D) * v)
end

"""
Closed-form five-segment chain (Proposition 1) for collinear inertial nodes
x_i(t) = xs[i] + vs[i] t. Returns (t1, t_commit, t_resp, bound).
"""
function closed_form_chain(c, xs, vs, client, leader, t0, Q)
    pos(i, t) = xs[i] + vs[i] * t
    t1 = client == leader ? t0 : closed_form_arrival(c, t0, pos(client, t0), xs[leader], vs[leader])
    acks = [t1]
    for p in eachindex(xs)
        p == leader && continue
        t2 = closed_form_arrival(c, t1, pos(leader, t1), xs[p], vs[p])
        push!(acks, closed_form_arrival(c, t2, pos(p, t2), xs[leader], vs[leader]))
    end
    t_commit = sort(acks)[Q]
    t_resp = client == leader ? t_commit :
             closed_form_arrival(c, t_commit, pos(leader, t_commit), xs[client], vs[client])
    return (t1=t1, t_commit=t_commit, t_resp=t_resp,
            bound=(t_resp - t0) * sqrt(1 - (vs[client] / c)^2))
end

"""Replace the worldlines of a canonical config by collinear inertial ones."""
function collinear_config(xs, vs; signal_speed=1.0)
    base = canonical_scenario(SeparatedStaticBaseline; cluster_size=length(xs), signal_speed=signal_speed)
    spacetime = base.spacetime
    worldlines = AbstractWorldline{Float64}[
        InertialWorldline(spacetime, (Float64(x), 0.0, 0.0), (Float64(v), 0.0, 0.0))
        for (x, v) in zip(xs, vs)
    ]
    return ScenarioConfig(
        base.name, base.family, spacetime, worldlines, base.raft, base.network, base.faults,
        base.workload, base.window, base.characteristic_distance, base.beta_scale,
        base.proper_acceleration_scale,
    )
end

fake_op(seq, kind, t0, latency; outcome=:committed) = OperationMetric(
    RelativisticDistributedSystemsSim.Raft.RequestID(UInt64(1), UInt64(seq)),
    kind, t0, t0, isnothing(latency) ? nothing : t0 + latency,
    isnothing(latency) ? nothing : t0 + latency, latency, outcome, 1,
)

@testset "causal quorum completion bounds (Claim C3)" begin
    @testset "co-located control has a zero bound" begin
        control = canonical_scenario(ColocatedControl; cluster_size=3)
        @test causal_quorum_bound(control, 1, 0.0) == 0.0
    end

    @testset "closed form: stationary collinear, client == leader and client != leader" begin
        for (xs, c) in (
            ([-0.04, 0.0, 0.04], 1.0),
            ([0.0, 0.07, 0.30, 0.31, 0.90], 1.0),
            ([0.0, 0.07, 0.30, 0.31, 0.90], 3.0),
            ([0.5, -0.2, 0.1, 0.35, -0.6, 0.0, 0.8], 1.0),
        )
            cfg = collinear_config(xs, zeros(length(xs)); signal_speed=c)
            N = length(xs)
            Q = N ÷ 2 + 1
            t0 = 1.25
            for client in (1, N), leader in 1:N
                ref = closed_form_chain(c, xs, zeros(N), client, leader, t0, Q)
                # Direct stationary formula: 2|x_L - x_C|/c + 2 d_(Q-1)/c.
                d = sort([abs(xs[p] - xs[leader]) for p in 1:N if p != leader])
                @test isapprox(ref.bound, 2abs(xs[leader] - xs[client]) / c + 2d[Q - 1] / c; rtol=1e-14)
                chain = causal_quorum_chain(cfg, client, t0, leader)
                @test isapprox(chain.t_leader_receive, ref.t1; rtol=1e-13)
                @test isapprox(chain.t_commit, ref.t_commit; rtol=1e-13)
                @test isapprox(chain.t_response, ref.t_resp; rtol=1e-13)
                @test isapprox(chain.bound, ref.bound; rtol=1e-12, atol=1e-14)
                @test isapprox(causal_quorum_bound(cfg, client, t0; leader_node=leader), ref.bound;
                               rtol=1e-12, atol=1e-14)
                # The replication-only variant drops the two client legs.
                repl = causal_quorum_chain(cfg, client, t0, leader; include_client_legs=false)
                @test isapprox(repl.bound, 2d[Q - 1] / c; rtol=1e-12, atol=1e-14)
            end
            for client in (1, N)
                expected = minimum(closed_form_chain(c, xs, zeros(N), client, L, t0, Q).bound for L in 1:N)
                @test isapprox(causal_quorum_bound(cfg, client, t0), expected; rtol=1e-12)
            end
        end
        # Documented special case (§4) for the canonical separated layout.
        static_cfg = canonical_scenario(SeparatedStaticBaseline; cluster_size=3)
        expected_rtt = 2.0 * dimensionless_parameters(static_cfg).rho * static_cfg.raft.heartbeat_interval
        @test isapprox(causal_quorum_bound(static_cfg, 1, 0.0; leader_node=1), expected_rtt; rtol=1e-12)
        @test isapprox(causal_quorum_bound(static_cfg, 1, 0.0), expected_rtt; rtol=1e-12)
    end

    @testset "closed form: collinear inertial receding / approaching, 5-segment chain" begin
        cases = (
            # receding fan (AsymmetricRecedingInertial-like), client at the origin
            ([0.0, 0.04, 0.08], [0.0, 0.25, 0.5], 1.0),
            # approaching nodes, moving client
            ([0.0, 0.3, -0.5, 0.9, 0.2], [0.2, -0.3, 0.25, -0.1, 0.0], 1.0),
            # mixed directions, c != 1
            ([0.1, -0.2, 0.05, 0.3, -0.15], [0.9, 0.6, -0.8, -0.3, 0.75], 3.0),
        )
        for (xs, vs, c) in cases, t0 in (0.0, 0.7, 2.3)
            cfg = collinear_config(xs, vs; signal_speed=c)
            N = length(xs)
            Q = N ÷ 2 + 1
            for client in 1:N
                refs = [closed_form_chain(c, xs, vs, client, L, t0, Q) for L in 1:N]
                for leader in 1:N
                    chain = causal_quorum_chain(cfg, client, t0, leader)
                    @test isapprox(chain.t_leader_receive, refs[leader].t1; rtol=1e-12)
                    @test isapprox(chain.t_commit, refs[leader].t_commit; rtol=1e-12)
                    @test isapprox(chain.t_response, refs[leader].t_resp; rtol=1e-12)
                    @test isapprox(chain.bound, refs[leader].bound; rtol=1e-11, atol=1e-14)
                end
                @test isapprox(causal_quorum_bound(cfg, client, t0), minimum(r.bound for r in refs);
                               rtol=1e-11, atol=1e-14)
            end
        end
        # Relativistic chase: legs that close only beyond the analysis horizon
        # are reported as unreachable (Inf), never as a finite underestimate.
        xs, vs, c = [0.0, 1.0, -1.0], [0.0, 0.99, -0.99], 1.0
        cfg = collinear_config(xs, vs; signal_speed=c)
        horizon = _C3._causal_bound_horizon(cfg, 0.0)
        for leader in 1:3
            ref = closed_form_chain(c, xs, vs, 1, leader, 0.0, 2)
            chain = causal_quorum_chain(cfg, 1, 0.0, leader)
            if ref.t_resp <= horizon
                @test isapprox(chain.bound, ref.bound; rtol=1e-11, atol=1e-14)
            else
                @test chain.bound == Inf
            end
        end
        @test causal_quorum_bound(cfg, 1, 0.0; leader_node=2) == Inf

        # Receding geometry: the bound grows with the invocation time.
        receding_cfg = canonical_scenario(AsymmetricRecedingInertial; cluster_size=3)
        early = causal_quorum_bound(receding_cfg, 1, receding_cfg.window.warmup_end_coordinate)
        late = causal_quorum_bound(receding_cfg, 1, receding_cfg.window.measurement_end_coordinate)
        @test 0.0 < early < late
    end

    @testset "oracle null solver agrees with engine solver on accelerated worldlines" begin
        cfg = canonical_scenario(AcceleratingBaseline; cluster_size=5)
        max_t = cfg.window.censor_coordinate + 100cfg.raft.election_timeout_max
        for from in 1:5, to in 1:5, t_e in (0.0, 1.0, 3.0)
            from == to && continue
            emission = worldline_event(cfg.worldlines[from], t_e)
            oracle = _C3._oracle_null_arrival(cfg.spacetime, t_e, emission.x, cfg.worldlines[to], max_t)
            engine = _C3._try_light_cone_intersection(cfg.spacetime, emission, cfg.worldlines[to], max_t)
            @test isfinite(oracle) == isfinite(engine)
            isfinite(oracle) && @test isapprox(oracle, engine; rtol=1e-10)
        end
    end

    @testset "scale-aware tolerance" begin
        @test causal_bound_tolerance(0.0) == CAUSAL_BOUND_ATOL_FLOOR
        @test causal_bound_tolerance(1.0e6) == CAUSAL_BOUND_RTOL * 1.0e6
        @test causal_bound_tolerance(2.0; rtol=1e-3, atol_floor=0.0) == 2.0e-3
    end

    @testset "negative controls: the oracle flags sub-bound completions" begin
        cfg = collinear_config([0.0, 0.07, 0.30, 0.31, 0.90], zeros(5))
        t0 = 1.0
        bound = causal_quorum_bound(cfg, cfg.workload.client_node, t0)
        @test bound > 0.1
        tol = causal_bound_tolerance(bound)

        below = verify_causal_quorum_bounds(cfg, [fake_op(1, :write, t0, bound * (1 - 1e-6))])
        @test !below.ok
        @test below.audited_writes == 1
        @test length(below.violations) == 1
        @test below.min_margin < 0

        within = verify_causal_quorum_bounds(cfg, [
            fake_op(1, :write, t0, bound),
            fake_op(2, :write, t0, bound - tol / 2),
            fake_op(3, :write, t0, bound + 0.25),
        ])
        @test within.ok
        @test within.audited_writes == 3
        @test isapprox(within.min_margin, -tol / 2; rtol=1e-6)

        # Reads and non-committed operations are not audited; committed writes
        # without a latency are violations.
        mixed = verify_causal_quorum_bounds(cfg, [
            fake_op(1, :read, t0, bound / 10),
            fake_op(2, :write, t0, bound / 10; outcome=:censored),
            fake_op(3, :write, t0, nothing),
        ])
        @test !mixed.ok
        @test mixed.audited_writes == 1
        @test isnan(mixed.min_margin)

        # A fixed far leader raises the bound, so a latency valid for the
        # minimum-over-leaders bound is flagged when that leader is imposed.
        far = causal_quorum_bound(cfg, 1, t0; leader_node=5)
        @test far > bound
        fixed = verify_causal_quorum_bounds(cfg, [fake_op(1, :write, t0, (bound + far) / 2)]; leader_node=5)
        @test !fixed.ok
    end

    @testset "vacuity rule: no committed writes gives NaN, never 0.0" begin
        cfg = canonical_scenario(SeparatedStaticBaseline; cluster_size=3)
        empty_audit = verify_causal_quorum_bounds(cfg, OperationMetric[])
        @test empty_audit.ok
        @test empty_audit.audited_writes == 0
        @test isnan(empty_audit.min_margin)
        @test isempty(empty_audit.violations)

        censored = verify_causal_quorum_bounds(cfg, [
            fake_op(1, :write, 1.0, nothing; outcome=:censored),
            fake_op(2, :read, 1.0, 0.5),
        ])
        @test censored.audited_writes == 0
        @test isnan(censored.min_margin)
    end

    @testset "simulated writes respect the bound (non-vacuous)" begin
        small_wl = WorkloadSpec(operation_count=4, read_every=0) # pure writes
        committing = (ColocatedControl, SeparatedStaticBaseline, PartitionDropStress)
        for family in instances(ScenarioFamily)
            config = canonical_scenario(family; cluster_size=3, workload=small_wl)
            result = run_scenario(config; seed=0x42)
            @test result.status == :completed
            committed_writes = count(
                op -> op.outcome == :committed && op.operation_kind != :read,
                result.operations,
            )
            # The engine hands client requests to the current leader and the
            # reply back to the client without propagation (instantaneous
            # client attachment), so the replication-only bound (segments 2-4)
            # is the one the engine is contractually bound by.
            audit = verify_causal_quorum_bounds(config, result.operations; include_client_legs=false)
            @test audit.ok
            @test isempty(audit.violations)
            @test audit.audited_writes == committed_writes
            if family in committing
                @test audit.audited_writes > 0
                @test audit.min_margin >= -causal_bound_tolerance(audit.min_margin)
            end
            # For n = 3 collinear static layouts every leader's quorum round
            # trip equals the client's own, so the full chain also holds.
            if family in (ColocatedControl, SeparatedStaticBaseline)
                full = verify_causal_quorum_bounds(config, result.operations)
                @test full.ok
                @test full.audited_writes > 0
            end
        end

        # Regression for DEVIATIONS.md D-14: with n = 5 a central leader closes
        # its quorum faster than an edge client can, so the full Proposition 1
        # chain is violated unless the engine propagates the client->leader
        # and leader->client legs.
        config5 = canonical_scenario(SeparatedStaticBaseline; cluster_size=5, workload=small_wl)
        result5 = run_scenario(config5; seed=0x42)
        full5 = verify_causal_quorum_bounds(config5, result5.operations)
        @test full5.audited_writes > 0
        @test full5.ok
        @test verify_causal_quorum_bounds(config5, result5.operations; include_client_legs=false).ok
    end
end
