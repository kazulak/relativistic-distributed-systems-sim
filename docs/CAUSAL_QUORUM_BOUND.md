# Causal Quorum Lower Bound in Relativistic Raft

Status: formal specification and verification contract for **Claim C3** (see [CLAIMS_AND_LIMITATIONS.md](CLAIMS_AND_LIMITATIONS.md)).

---

## 1. Motivation and Problem Statement

In an asynchronous distributed consensus system such as Raft, operations are ordered and committed only after a leader replicates an entry to a strict majority quorum $Q$ of members ($|Q| > |N| / 2$) and receives acknowledgements confirming that the entry is durably recorded.

In flat Minkowski spacetime with signal speed $c$, direct information transfer between any two spacetime events $A$ and $B$ is restricted by the future light cone:
$$s^2(A, B) = c^2 (t_B - t_A)^2 - \|\mathbf{x}_B - \mathbf{x}_A\|^2 \ge 0, \quad t_B \ge t_A.$$

A strict-quorum write operation cannot complete before the causal round-trip path connecting the client, the leader, and a majority quorum of followers has closed. Any claim that a policy, timeout adaptation, or prediction overcomes this limit is physically impossible. This document formalizes **Proposition 1 (Causal Quorum Completion Bound)** and provides its verification contract.

---

## 2. Formal System and Spacetime Model

Let:
1. $\mathcal{M} = (\mathbb{R}^{1,3}, \eta)$ be Minkowski spacetime with signature $(+---)$ and invariant signal speed $c > 0$.
2. $\mathcal{S} = \{1, 2, \dots, N\}$ be a static Raft cluster of $N$ processes, where each process $i \in \mathcal{S}$ moves along a future-directed timelike worldline $\mathbf{x}_i(t)$ with $\|\mathbf{v}_i(t)\| < c$.
3. Process local monotonic clocks measure proper time:
   $$\tau_i(t) = \int_{t_{\text{start}}}^t \sqrt{1 - \frac{\|\mathbf{v}_i(t')\|^2}{c^2}} \, dt'.$$
4. A client $C$ (which may be co-located with a node or an independent process) initiates a write operation at coordinate time $t_0$, corresponding to client proper time $\tau_C(t_0)$.
5. Quorum size is $Q = \lfloor N / 2 \rfloor + 1$.

---

## 3. Proposition 1: Causal Quorum Completion Bound

### Proposition Statement
For any strict-quorum Raft write operation invoked by client $C$ at coordinate time $t_0$, let $L \in \mathcal{S}$ be the cluster leader that accepts the request. The earliest possible coordinate time $t_{\text{resp}}$ at which client $C$ can receive a valid committed completion response satisfies:

$$t_{\text{resp}} \ge t_{\text{causal\_bound}}(C, L, t_0),$$

and the elapsed proper time measured on the client's local clock satisfies:

$$\Delta \tau_{\text{client}} = \tau_C(t_{\text{complete}}) - \tau_C(t_0) \ge \Delta \tau_{\text{causal\_bound}}(C, L, t_0),$$

where $\Delta \tau_{\text{causal\_bound}}(C, L, t_0) = \int_{t_0}^{t_{\text{causal\_bound}}} \sqrt{1 - \|\mathbf{v}_C(t)\|^2/c^2} \, dt$.

### Derivation

The causal chain of any lawful Raft replicated write consists of five sequential segments (four physical signal legs plus the quorum-commit step at the leader):

1. **Client-to-Leader Delivery ($C \to L$):**
   The client invokes the write at event $E_0 = (t_0, \mathbf{x}_C(t_0))$. The message travels forward along or inside the future light cone to leader $L$. The earliest arrival event at $L$ is the future null intersection $E_1 = (t_1, \mathbf{x}_L(t_1))$ satisfying:
   $$c (t_1 - t_0) = \|\mathbf{x}_L(t_1) - \mathbf{x}_C(t_0)\|, \quad t_1 \ge t_0.$$

2. **Leader-to-Peers Outbound Replication ($L \to p$):**
   Upon receiving the request at $t_1$, leader $L$ logs the entry and emits `AppendEntries` requests to all peers $p \in \mathcal{S} \setminus \{L\}$. For each peer $p$, the earliest possible delivery event $E_{2,p} = (t_{2,p}, \mathbf{x}_p(t_{2,p}))$ satisfies:
   $$c (t_{2,p} - t_1) = \|\mathbf{x}_p(t_{2,p}) - \mathbf{x}_L(t_1)\|, \quad t_{2,p} \ge t_1.$$

3. **Peer Acknowledgement Return ($p \to L$):**
   Upon delivery at $t_{2,p}$, peer $p$ appends the entry to its log and sends an `AppendEntriesResponse` back to leader $L$. The earliest return event $E_{3,p} = (t_{3,p}, \mathbf{x}_L(t_{3,p}))$ at the leader satisfies:
   $$c (t_{3,p} - t_{2,p}) = \|\mathbf{x}_L(t_{3,p}) - \mathbf{x}_p(t_{2,p})\|, \quad t_{3,p} \ge t_{2,p}.$$
   For the leader itself ($p = L$), local logging requires $t_{3,L} = t_1$.

4. **Quorum Commit at Leader:**
   Raft safety requires that a leader commit an entry only when it has been replicated on a majority of servers. Let $\{t_{3,(1)}, t_{3,(2)}, \dots, t_{3,(N)}\}$ be the sorted order of acknowledgement arrival times at $L$ (with $t_{3,(1)} = t_1$ for $L$ itself). The leader reaches quorum commit at the earliest coordinate time:
   $$t_{\text{commit}} = t_{3,(Q)}.$$

5. **Leader-to-Client Response Delivery ($L \to C$):**
   Having committed the entry, the leader sends the client reply at $E_{\text{commit}} = (t_{\text{commit}}, \mathbf{x}_L(t_{\text{commit}}))$. The earliest event $E_{\text{resp}} = (t_{\text{resp}}, \mathbf{x}_C(t_{\text{resp}}))$ at which the client receives the reply satisfies:
   $$c (t_{\text{resp}} - t_{\text{commit}}) = \|\mathbf{x}_C(t_{\text{resp}}) - \mathbf{x}_L(t_{\text{commit}})\|, \quad t_{\text{resp}} \ge t_{\text{commit}}.$$

Because physical message transmission cannot exceed signal speed $c$, any additional delays (queueing, processing, serialization, media index $n > 1$) can only increase delivery coordinate times:
$$t_{\text{complete}} \ge t_{\text{resp}} \ge t_{\text{causal\_bound}}.$$

$\blacksquare$

### Leader identity, redirects, and leader changes

The accepting leader $L$ is not known in advance: Raft may elect any member, and the leader can change while a write is in flight. The oracle therefore uses
$$\Delta \tau_{\text{causal\_bound}}(C, t_0) = \min_{L \in \mathcal{S}} \Delta \tau_{\text{causal\_bound}}(C, L, t_0),$$
which is a valid lower bound whichever member ends up committing the entry. Additional protocol behaviour can only lengthen the chain, never shorten it:

- **Redirects.** A request first sent to a non-leader $F$ and redirected (by the client after a `NotLeader` hint, or forwarded by $F$) reaches $L$ no earlier than the direct null leg $C \to L$ would, because the path $C \to F \to L$ is a causal chain from $E_0$ and every causal curve from $E_0$ to $L$'s worldline meets it no earlier than the future null intersection $t_1$.
- **Leader changes / retries.** If the request is re-submitted to a new leader $L'$, the eventual commit and response are still causally downstream of $E_0$ through $L'$, so the elapsed time is bounded by the chain for $L'$, which is at least the minimum over leaders. Retries only add legs.
- **Heartbeat-piggybacked replication and batching** delay the $L \to p$ emission past $t_1$ and cannot move it earlier.

The minimum over leaders is attained with the client's own node as leader in some geometries (then segments 1 and 5 vanish) and by a more central node in others; see §4.

---

## 4. Special Case: Stationary Inertial Layout

For a co-located client-leader $C = L$ at rest with stationary peers at distance $d_p = \|\mathbf{x}_p - \mathbf{x}_L\|$:
1. $t_1 = t_0$.
2. For each peer $p$, round-trip light time is $\Delta t_p = 2 d_p / c$.
3. Arranging peers by increasing distance $d_{(1)} \le d_{(2)} \le \dots \le d_{(N-1)}$:
   $$t_{\text{commit}} = t_0 + \frac{2 d_{(Q-1)}}{c}.$$
4. Client is co-located with leader, so $t_{\text{resp}} = t_{\text{commit}}$.
5. Proper time equals coordinate time:
   $$\Delta \tau_{\text{causal\_bound}} = \frac{2 d_{(Q-1)}}{c}.$$

For a stationary client $C \ne L$ at distance $D_{CL}$ from the leader, the two client legs add $2 D_{CL}/c$:
$$\Delta \tau_{\text{causal\_bound}}(C, L) = \frac{2 D_{CL}}{c} + \frac{2 d_{(Q-1)}(L)}{c}.$$
Example: five collinear equally spaced nodes (spacing $s$), client at an end node. With $L = C$, $d_{(2)} = 2s$ and the bound is $4s/c$; with $L$ the centre node the replication round trip is only $2s/c$ but the client legs add $4s/c$ (total $6s/c$). The minimum over leaders is $4s/c$.

---

## 5. Verification Contract and Assertion Oracle

### 5.1 Implemented oracle

`src/Research/Scenarios.jl` implements Proposition 1 as follows.

- `causal_quorum_chain(config, client_node, t0, leader_node; include_client_legs=true)` evaluates the five segments of §3 for one fixed leader. It returns `(leader, t_invoke, t_leader_receive, t_commit, t_response, bound)`: $t_1$ (equal to $t_0$ when the client node is the leader), $t_{\text{commit}}$ as the $Q$-th smallest acknowledgement time with the leader's own log write counted at $t_1$, $t_{\text{resp}}$, and the client proper time $\tau_C(t_{\text{resp}}) - \tau_C(t_0)$.
- `causal_quorum_bound(config, client_node, t0; leader_node=nothing, include_client_legs=true)` returns the minimum of `bound` over all members (see "Leader identity" in §3), or the value for a fixed `leader_node`.
- `verify_causal_quorum_bounds(config, operations; leader_node=nothing, include_client_legs=true, rtol, atol_floor)` audits every `:committed` non-read operation in the run and returns `(ok, audited_writes, min_margin, violations)`, with $\text{margin} = (\tau_{\text{complete}} - \tau_{\text{invoke}}) - \Delta \tau_{\text{causal\_bound}}$.

The oracle records a violation when any of the following holds:
1. the margin is below $-\epsilon$ (see §5.2);
2. the operation committed but its bound is infinite, meaning no leader can close the chain before the analysis horizon $\max(t_{\text{censor}}, t_0) + 100\,T_{\text{election,max}}$;
3. the operation is committed but has no recorded latency.

`ok` means only that the violation list is empty.

`include_client_legs=false` drops segments 1 and 5, so that $t_1 = t_0$ and $t_{\text{resp}} = t_{\text{commit}}$. This gives a weaker replication-only bound for a client model in which the client is attached to whichever node leads, with no signal propagation between them. **Engine status:** since the D-14 fix (`DEVIATIONS.md`), `src/Research/Engine.jl` propagates client requests and replies along the light cone (plus processing delay) and causality-checks them on arrival, so the default full-chain audit applies to simulation output. Before that fix the engine delivered client traffic with zero propagation delay and violated the full chain whenever a leader other than the client's node was closer to its quorum (for example, `SeparatedStaticBaseline` with $N = 5$); that case is now a regression test in `test/research/causal_bounds.jl`.

### 5.2 Tolerance

The tolerance scales with the size of the quantities being compared:
$$\epsilon = \max\big(\epsilon_{\text{floor}},\ \text{rtol} \cdot \max(\Delta\tau_{\text{causal\_bound}}, \Delta\tau_{\text{measured}})\big),$$
with $\text{rtol} = 10^{-9}$ (`CAUSAL_BOUND_RTOL`) and $\epsilon_{\text{floor}} = 4096\,\varepsilon_{\text{Float64}} \approx 9.09 \times 10^{-13}$ (`CAUSAL_BOUND_ATOL_FLOOR`, in client proper-time units). The tolerance function is exposed as `causal_bound_tolerance(scale; rtol, atol_floor)`.

The relative term covers two effects that grow with the magnitude of the times involved. First, the engine's light-cone solver has relative tolerance $512\,\varepsilon$. Second, proper-time quadrature accumulates rounding error, and the absolute size of that error grows with the coordinate epoch. The floor matters only when a bound is close to zero, as in the co-located control. Real causality defects are many orders of magnitude larger: the engine shortcut above gives margins of about $-0.07$ against a tolerance of about $1.6 \times 10^{-10}$.

### 5.3 Independence from the engine

The oracle does **not** call the engine's transport solver (`light_cone_intersection` / `_try_light_cone_intersection`). Each null leg is solved separately by `_oracle_null_arrival`, a bracketed bisection on
$$f(t) = c\,(t - t_e) - \|\mathbf{x}_R(t) - \mathbf{x}_e\|.$$
For a timelike receiver, $f'(t) \ge c - \|\mathbf{v}_R\| > 0$, so $f$ has a unique root on $[t_e, \infty)$. The solver returns the lower bracket end, for which $f < 0$. That value is at or before the true arrival, so the oracle cannot overstate the bound because of solver error.

The oracle still shares two things with the engine: worldline kinematics (`worldline_event` positions) and `proper_time_between`.

The test suite checks both the oracle and those shared pieces against closed-form references that use neither solver. For one-dimensional constant-velocity motion $x_R(t) = x_0 + v t$, write the receiver's offset at emission as $D = x_0 + v t_e - x_e$. Because $|v| < c$, the receiver stays on the same side of $x_e$ until the signal reaches it. The null condition is therefore linear in $t$:
$$t = t_e + \frac{|D|}{c - \operatorname{sign}(D)\, v},$$
and the proper time is $\Delta \tau = (t_{\text{resp}} - t_0)\sqrt{1 - v_C^2/c^2}$.

`test/research/causal_bounds.jl` checks the following:
- The oracle matches this closed form to relative error $10^{-11}$–$10^{-13}$ at every chain stage, for every leader.
- Those configurations include stationary non-uniform layouts, $N \in \{3, 5, 7\}$, $c \in \{1, 3\}$, clients at both ends (so client ≠ leader), and receding or approaching inertial layouts with a moving client.
- On `UniformlyAcceleratedWorldline` layouts, the oracle's null solver agrees with the engine solver to relative error $10^{-10}$.

### 5.4 Vacuity rule

A run with no committed writes gives no evidence for C3. In that case `verify_causal_quorum_bounds` returns `audited_writes == 0` and `min_margin = NaN`, never `0.0`. Summaries must report `audited_writes` next to any margin statistic, and must not count runs with `audited_writes == 0` as passing checks.

Some canonical defaults commit few or no writes. For example, `AsymmetricRecedingInertial` with $N = 3$ commits 0 writes for seeds 1–3 under the default workload, and `AcceleratingBaseline` commits few or none.

### 5.5 Negative controls

The tests confirm that the oracle actually rejects violations:
- A synthetic `OperationMetric` whose latency is $\Delta\tau_{\text{causal\_bound}}(1 - 10^{-6})$ is flagged.
- Latencies at the bound, or within $\epsilon/2$ below it, are accepted.
- A committed write with no recorded latency is flagged.
- Reads and non-committed operations are not audited.
- Fixing a far leader (`leader_node`) raises the bound and flags a latency that the minimum over leaders accepts.

A margin below $-\epsilon$ in experiment output means a critical simulator failure: superluminal information delivery or a non-physical client attachment. Experiments must report it and must not average it away.
