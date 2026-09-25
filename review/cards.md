# Data-extraction cards

One card per included study (34). Extracted by Claude Code from the full texts in `review/pdf/`; the author approved screening and eligibility at the checkpoints.

Conventions: page numbers are PDF page numbers of the retrieved file (for the Ongaro thesis, printed page = PDF page − 18). Where the retrieved file is a preprint, the card says so; the reference gives the published version where one exists. "Not reported" means the item was looked for and not found in the text. Quotations are under 15 words.

### aeini2026
- **Full reference:** K. Aeini, W. Golab. "Analyzing Linearizability in Relativistic Distributed Systems." ACM, 2026. doi:10.1145/3820355.3820388
- **Communication model:** Relativistic: N processors subject to motion and gravitational effects; an execution is a history H = (E, <E) whose partial order is physical causality, invariant across frames; each event has a position in four-dimensional spacetime; physical causality refines Lamport's happens-before (p. 2). Algorithms analysed are asynchronous (p. 1, p. 8).
- **Properties analysed:** safety: relativistic linearizability R1, R2 and R3 (R1: linearizable in some frame; R2: in every frame; R3: one linearization valid in all frames, p. 1).
- **Method:** mathematical proof using Gilbert and Golab's technique (connected histories and R2-conducive R1-linearizations, Theorem 3.7).
- **Raft mechanisms and timing/clock assumptions as stated:** Operations are modelled as commands in the replicated log; the canonical linearization is the final leader's log order (p. 5). Election timeout discussed only as a cause of elections: "the heartbeat timeout is measured locally by each server, and therefore is immune to the time dilation and length contraction effects" (p. 4). Leases and ReadIndex are not modelled.
- **Physical parameters:** none quantitative; motivates with Hafele–Keating airborne clocks (p. 1).
- **Key results:** Theorem 4.1: any history of Raft is R3-linearizable, with the log order as its R3-linearization (p. 5). ABD is R3-linearizable in special cases; quorum key-value stores discussed informally (pp. 2, 8). Jayanti's theorem corresponds to R2 and "neither contradicts nor proves" the Gilbert–Golab conjecture (p. 2). Future work names "a systematic study of relativistic linearizability for algorithms that break the asynchronous assumption by using physical clocks for coordination" (p. 8).
- **Relevance:** RQ1 and RQ3 (safety of Raft under relativistic causality); RQ4 (explicitly leaves clock-based coordination open, p. 8). Also the only retrieved secondary account of Gilbert and Golab's R1–R3 definitions (gilbert2014 full text not retrieved).
- **Limitations:** Covers log-based operations only; no read optimisations or leases. The PDF is the arXiv preprint (the published version appeared at an ACM workshop, DOI 10.1145/3820355.3820388).
- **Extraction confidence:** high

### alquraan2018
- **Full reference:** A. Alquraan, H. Takruri, M. Alfatafta, S. Al-Kiswany. "An Analysis of Network-Partitioning Failures in Cloud Systems." 13th USENIX Symposium on Operating Systems Design and Implementation (OSDI 18), 2018. url:https://www.usenix.org/conference/osdi18/presentation/alquraan
- **Communication model:** Network-partitioning faults: complete, partial (some nodes reachable by only part of the cluster) and simplex (one-directional) partitions (pp. 3, 8).
- **Properties analysed:** safety violations (data loss, stale and dirty reads, two leaders) and availability, observed in real systems.
- **Method:** empirical study of 136 real failures in 25 distributed systems (issue trackers and Jepsen reports); reproduction and a testing framework (NEAT) (pp. 4–5).
- **Raft mechanisms and timing/clock assumptions as stated:** Leader election is the most vulnerable mechanism (affected by 40% of failures), the most common flaw being two simultaneous leaders: an isolated old leader keeps serving reads from its local copy until it steps down (p. 7). Raft-based RethinkDB is among the systems where an isolated leader still answers reads (p. 7). Systems implementing Paxos or Raft "often tweak these protocols in unproven ways" (p. 4).
- **Physical parameters:** not reported.
- **Key results:** 80% of failures are catastrophic, 90% silent, 21% cause permanent damage (Findings 1–3, p. 6); 88% can be triggered by isolating a single node (p. 3); 29% are caused by partial partitions and 2% by simplex partitions (p. 8); most need three or fewer events and three nodes (p. 9).
- **Relevance:** RQ1 (partition models; empirical evidence); RQ2 (stale reads from an isolated leader are the failure mode that leases or ReadIndex must prevent).
- **Limitations:** Characterisation study; implementations, not protocols; no clock analysis.
- **Extraction confidence:** high

### ashby2003
- **Full reference:** N. Ashby. "Relativity in the Global Positioning System." Living Reviews in Relativity, 2003. doi:10.12942/lrr-2003-1
- **Communication model:** One-way timing signals from satellite clocks at speed c; receivers solve propagation-delay equations (p. 6). Synchronisation of all ground and orbiting clocks is performed in the Earth-centred inertial (ECI) frame (p. 9).
- **Properties analysed:** accuracy of time transfer and positioning; clock rate corrections. No protocol safety or liveness.
- **Method:** analytical (special and general relativity, Keplerian orbits); experimental data (NTS-2, TOPEX/POSEIDON).
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable. Clock synchronisation convention stated explicitly: ECI frame (p. 9); the Sagnac effect "can be regarded as arising from the relativity of simultaneity" (p. 9).
- **Physical parameters:** GPS orbit; clock class: Cesium and Rubidium atomic clocks (pp. 16–17). Net constant fractional rate correction for a GPS satellite clock (gravitational blueshift combined with second-order Doppler): −4.4647 × 10⁻¹⁰ (+2.5046 × 10⁻¹⁰ − 6.9693 × 10⁻¹⁰, Eq. 35, p. 16). Gravitational and velocity effects cancel at orbit radius a ≈ 9545 km; for a low orbit (Space Shuttle) time dilation dominates (p. 16). NTS-2 measured +442.5 parts in 10¹² against predicted +446.5 (pp. 16–17). Eccentricity correction up to about 23 ns for e = 0.01 (p. 17). A 1 ns timing error gives about 30 cm position error (p. 6). The Sagnac effect in common-view comparisons "can amount to hundreds of nanoseconds" (p. 9).
- **Key results:** Relativistic frequency shifts are large enough that GPS "would not work" without correcting them (p. 1); satellite clocks are pre-set lower in frequency to 10.229 999 995 43 MHz (p. 16).
- **Relevance:** RQ3 (quantified relativistic timekeeping in an operational distributed clock system); RQ4 (synchronisation is defined by a frame convention, ECI, not frame-invariantly).
- **Limitations:** Navigation and time transfer only; no computational coordination model. The draft's Table 4 value "4.5 × 10⁻¹⁰, gravitational" corresponds here to the *net* gravitational-plus-velocity term.
- **Extraction confidence:** high

### davis2025
- **Full reference:** A. J. J. Davis, M. Demirbas, L. Deng. "LeaseGuard: Raft Leases Done Right." 2025. doi:10.1145/3786663
- **Communication model:** Raft's crash-fault asynchronous replication, with messages subject to delay; deposed leaders may be partitioned (p. 1). Simulation parameters include network latency mean and variance and maximum clock-error bounds (p. 7). Evaluation adds 1–10 ms one-way latency (Fig. 6, p. 8).
- **Properties analysed:** safety (linearizability of lease reads, pp. 5–6); availability and latency during failover; throughput.
- **Method:** TLA+ specification and model exploration (p. 3, p. 7); prose correctness argument (Section 4, pp. 5–6); Python simulation; LogCabin implementation.
- **Raft mechanisms and timing/clock assumptions as stated:** Lease reads; Raft elections left unmodified (p. 4). Clock assumption: "Clocks with bounded uncertainty": each node has intervalNow() returning [earliest, latest] such that "the true time was in this interval for at least a moment"; t1 is more than Δ old if t1.latest + Δ < t2.earliest (p. 3). All nodes share lease duration Δ (p. 3). Correctness is first shown "assuming perfect clocks", then with clock uncertainty (p. 5). If a clock's bounds are wrong, "multiple leaders may think they are leaseholders at once" and linearizability is violated; "Inherited lease reads require correct clock bounds!" (p. 6).
- **Physical parameters:** clock classes: TrueTime average error 4 ms in 2012; Meta sub-microsecond; AWS servers used in the evaluation have average clock error below 50 µs (p. 3). No distances or velocities.
- **Key results:** Lease reads cut consistent-read overhead from one network round trip to zero; write throughput rises from about 1,000 to about 10,000 writes/s; a new leader allows 99% of reads immediately instead of blocking all reads (p. 1). Prior Raft lease implementations are reported to have open stale-read bugs (etcd, 2024) and long unavailability after elections (TiDB, 10 s) (p. 1).
- **Relevance:** RQ2 (the lease is the clock-dependent safety mechanism; its assumption is stated as bounded clock *uncertainty relative to true time*, not as a drift-rate bound); RQ4 (the assumption presupposes a single "true time", a global simultaneity convention).
- **Limitations:** The correctness argument is prose over a TLA+ model; clock bounds are assumed correct, not derived. The PDF is the arXiv preprint (published in PACMMOD, DOI 10.1145/3786663).
- **Extraction confidence:** high

### howard2014
- **Full reference:** H. Howard. "ARC: Analysis of Raft Consensus." University of Cambridge, Computer Laboratory, 2014. url:https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-857.pdf
- **Communication model:** Unreliable network with delays, partitions, packet loss, duplication and reordering (stated for Multi-Paxos assumptions, p. 15, and simulated per packet from a delay distribution with loss and duplication, p. 35); LAN calibration with long-tailed delay and no loss (p. 41); partitions and asymmetric partitions (pp. 21, 55).
- **Properties analysed:** availability (election time), client latency, correctness (liveness bug), understandability.
- **Method:** discrete-event simulation of an OCaml implementation; calibration against the original Raft LAN experiment.
- **Raft mechanisms and timing/clock assumptions as stated:** Follower, candidate and client timers analysed separately; binary exponential backoff on the candidate timer (pp. 55–56). Leader-only reads recommended "assuming that the leader has committed an entry from its term and recently dispatched a successful AppendEntries to a majority of nodes" (p. 56); no clock bound is stated for "recently".
- **Physical parameters:** five nodes, 1 Gb/s Ethernet, average broadcast time 15 ms (p. 41). No clock parameters.
- **Key results:** Raft "behaves admirably" in a well-understood network with suitable parameters, but "a cluster can be rendered useless by a frequently disconnected node or a node with an asymmetric partition (such as behind a NAT)" (p. 55). Separating follower and candidate timeouts and adding backoff improves election performance; a commit-blocking liveness bug fixed by no-op entries (pp. 55–56).
- **Relevance:** RQ1 (simulation under lossy, partitioned and asymmetric networks); RQ2 (early statement of availability problems under partial connectivity; lease-like read rule without an explicit clock assumption).
- **Limitations:** Undergraduate dissertation published as a technical report; the conference version is howard2015; asymmetric-partition claim is stated in the conclusion with limited detail in the extracted pages.
- **Extraction confidence:** medium

### howard2015
- **Full reference:** H. Howard, M. Schwarzkopf, A. Madhavapeddy, J. Crowcroft. "Raft Refloated: Do We Have Consensus?" ACM SIGOPS Operating Systems Review, 2015. doi:10.1145/2723872.2723876
- **Communication model:** Asynchronous: no upper bound on message delay or computation time, no global clock synchronisation; unreliable network with delay, partitions, loss, duplication and reordering; no Byzantine failures (p. 2). Simulation reproduces the LAN experiment with a long-tailed packet delay and no packet loss (TCP) (p. 7).
- **Properties analysed:** leader-election latency (availability); safety (trace checking); livelock.
- **Method:** event-driven simulation calibrated against the original LogCabin experiment; safety checking of over 100,000 traces against a finite-automaton model (SPL) (p. 1, p. 8).
- **Raft mechanisms and timing/clock assumptions as stated:** Separates follower, candidate, leader and client timeouts (p. 2); leader timeout set to half the lower follower-timeout bound (p. 7).
- **Physical parameters:** five nodes, 1 Gb/s Ethernet, average broadcast time 15 ms in the original setup (p. 7). No clock parameters.
- **Key results:** Reproduction broadly matches the original election-time CDFs, taking longer under high contention (p. 7). Candidate-timeout optimisations (fixed reduction, binary exponential backoff): for 150–155 ms follower timeouts the mean packets to elect a leader fall from 108.2 to 48.6 with both combined (Table 1, p. 7). No safety violation observed; permanent livelock observed in some traces from the interaction of the commitment rule and the client request cache, fixed by a no-op entry (p. 8).
- **Relevance:** RQ1 (simulation under an explicit asynchronous, lossy model); RQ2 (timeouts affect availability, not safety).
- **Limitations:** LAN-calibrated; no loss in the reproduced experiments; livelock analysis deferred to a technical report (p. 8).
- **Extraction confidence:** high

### howard2025
- **Full reference:** H. Howard, M. A. Kuppe, E. Ashton et al. "Smart Casual Verification of the Confidential Consortium Framework." 22nd USENIX Symposium on Networked Systems Design and Implementation (NSDI 25), 2025. url:https://www.usenix.org/conference/nsdi25/presentation/howard
- **Communication model:** Spec models in-transit messages as a set, supporting ordered or unordered delivery abstractions (p. 6); non-determinism in timeouts and message delivery; crashes and message loss (p. 2). Host, OS, network and storage untrusted at the platform level (p. 3), but the consensus protocol is crash fault-tolerant (p. 4).
- **Properties analysed:** safety and liveness of CCF's Raft-derived consensus and its client consistency model.
- **Method:** "smart casual verification": TLA+ specification, model checking and simulation with TLC, and trace validation of the C++ implementation against the spec (p. 3, p. 8).
- **Raft mechanisms and timing/clock assumptions as stated:** Election timeouts, CheckQuorum, and a "partition leader step down" extension, motivated because "partial/asymmetric network partitions can cause a loss of liveness" in base Raft: a leader that cannot receive messages keeps sending heartbeats and prevents followers from timing out (p. 5). Time progression is modelled as independent of other actions (p. 7). No clock-rate assumptions reported.
- **Physical parameters:** not reported.
- **Key results:** Six bugs found before production: five safety (e.g. incorrect election quorum tally allowing two leaders in one term; commit advance for a previous term; truncation of committed entries from stale AE-NACKs) and one liveness (premature node retirement) (Table 2, p. 11).
- **Relevance:** RQ1 (model checking of a Raft variant under an explicit lossy, reordering network abstraction); RQ2 (liveness under partial/asymmetric partitions requires extensions).
- **Limitations:** CCF-specific protocol; safety bugs are implementation-spec divergences rather than communication-model results.
- **Extraction confidence:** high

### hu2026
- **Full reference:** Z. Hu, T. Dan, Z. Tao et al. "RUBICONe: Wireless RAFT-Unified Behaviors for Intervehicular Cooperative Operations and Negotiations." arXiv, 2026. arXiv:2603.18595
- **Communication model:** IEEE 802.11p vehicular channels with Rayleigh fading, Doppler shifts and CSMA/CA; packet loss, variable latency and signal degradation (p. 2). The baseline reliability model assumes independent packet loss (p. 4).
- **Properties analysed:** "system reliability" (probability of a correct consensus decision), robustness, effective cluster size vs. SNR (pp. 4–5).
- **Method:** hardware-in-the-loop testbed on software-defined radios (GNU Radio 802.11p stack) plus simulation (pp. 4–5).
- **Raft mechanisms and timing/clock assumptions as stated:** RAFT-like roles; leader chosen primarily by SNR; election timeout T_election,i = (1 + α Σ γ_ij) T_base, scaled by link quality and neighbour density (Eq. 1, p. 3); deterministic SNR-weighted tie-breaking replaces randomised timeouts for split votes (p. 3). Heartbeats carry a timestamp (p. 3).
- **Physical parameters:** 5.9 GHz centre frequency, 10 MHz bandwidth, clock accuracy ±0.5 ppm VCTCXO, 3–27 Mbit/s (Table I, p. 5); SNR conditions 4 dB and 14 dB; clusters N = 1–11 (p. 5).
- **Key results:** Cluster connectivity falls with SNR; stable above about 8 dB; larger clusters are more sensitive to channel degradation (p. 5). System reliability rises sub-linearly with N; at low SNR the benefit of scaling is attenuated by packet loss (pp. 5–6).
- **Relevance:** RQ1 (Raft-like protocol under a physical wireless channel model, testbed); RQ2 (election timeout adapted to link quality).
- **Limitations:** "Reliability" concerns the correctness of perception votes, not replication safety; small clusters; preprint.
- **Extraction confidence:** medium

### huang2018
- **Full reference:** D. Huang, X. Ma, S. Zhang. "Performance Analysis of the Raft Consensus Algorithm for Private Blockchains." 2018. doi:10.1109/TSMC.2019.2895471
- **Communication model:** Independent heartbeat loss with packet-loss rate p per heartbeat interval; election timeout expressed as K heartbeat intervals; discrete time (Markov chain, p. 3). "Network split" = more than half of nodes out of the current leader's control (p. 1).
- **Properties analysed:** availability (probability and time to network split, which forces a new election).
- **Method:** analytical (absorbing Markov chain) validated by a Raft simulator (pp. 1, 6).
- **Raft mechanisms and timing/clock assumptions as stated:** Election timer decremented per missed heartbeat and reset on receipt (Eqs. 1–3, p. 3); election timeout range collapses to one value when its spread is small (p. 3). Vote denial within the minimum election timeout of hearing from the leader (p. 2).
- **Physical parameters:** not reported (loss rates 0.1–0.3; network sizes; K = 3–6).
- **Key results:** With p = 0.1 and N = 5, expected time to split is about 1,000 steps for K = 3 and 10,000 for K = 4, so one extra heartbeat prolongs stability about tenfold; with p = 0.3 about 50 and 110 (p. 6). Larger networks have smaller split probability; increasing the election timeout lowers split probability, especially at low loss (p. 6).
- **Relevance:** RQ1 (probabilistic-loss model; analytical method); RQ2 (election timeout vs. loss affects availability only).
- **Limitations:** Independence assumptions; heartbeat loss only, no delay distribution; blockchain framing. The PDF is the arXiv preprint (published in IEEE Trans. SMC: Systems, 2019).
- **Extraction confidence:** high

### jeffery2023
- **Full reference:** A. Jeffery, H. Howard, R. Mortier. "Mutating Etcd Towards Edge Suitability." arXiv, 2023. arXiv:2311.09929
- **Communication model:** Edge deployments across geographically distributed sites with unreliable latency and bandwidth (p. 2); partitions injected with iptables and delays with Linux traffic control (10% variation, 25% correlation) (p. 9).
- **Properties analysed:** availability and latency of etcd (Raft) versus CRDT-based variants under partitions and added latency; consistency guarantees compared (Table 3, p. 7).
- **Method:** system design (mergeable-etcd, dismerge) and emulated experiments (p. 9).
- **Raft mechanisms and timing/clock assumptions as stated:** etcd is "a Raft-based linearizable distributed key-value store, requiring majority quorums"; only the leader processes writes and linearizable reads, so requests are forwarded (p. 2). No clock assumptions reported.
- **Physical parameters:** added per-link latency (values in Figs. 11–12 not extracted); target rate 10,000 req/s in scaling experiments (p. 10).
- **Key results:** etcd cannot process requests without a majority, "leaving partitioned sites unable to adapt" (p. 2); after a partition heals, the local node is overloaded ("too many requests") and incurs forwarding latency (p. 9). The CRDT variants keep processing during partitions and synchronise afterwards (p. 9); etcd latency grows with cluster size (p. 10).
- **Relevance:** RQ1 (Raft/etcd under edge partitions and latency; low relevance, as the proposed systems abandon Raft's linearizability).
- **Limitations:** Evaluates a trade-off away from Raft; preprint.
- **Extraction confidence:** medium

### jensen2021
- **Full reference:** C. Jensen, H. Howard, R. Mortier. "Examining Raft's Behaviour during Partial Network Failures." ACM, 2021. doi:10.1145/3447851.3458739
- **Communication model:** Full and partial network partitions (in a partial partition A cannot reach B but both reach C, p. 2); intermittent partitions switching every 10 s (Fig. 8, p. 6); edge-style topology with 40 ms links (Fig. 10, p. 6). Emulated with Mininet; failures injected with iptables (pp. 3–4).
- **Properties analysed:** availability (request success rate; leader elections), latency.
- **Method:** emulation of production etcd with the reckon tool (testbed-like).
- **Raft mechanisms and timing/clock assumptions as stated:** Election timeout triggers candidacy when a follower has not heard from the leader (p. 2). CheckQuorum in etcd: a node with a stable leader ignores election requests; enabled for followers but disabled for leaders in the tested version (p. 5). PreVote: a node first checks it can be elected before calling an election (p. 6).
- **Physical parameters:** write load 1000 req/s (p. 4); 40 ms links, 80 ms RTT (p. 6). No clock parameters.
- **Key results:** Plain Raft under a partial partition may cycle through elections (Fig. 5a, p. 4). etcd behaves differently: because of its CheckQuorum variant there are no elections during the partial partition, only one when it heals, and about one third of requests are delayed by client round-robin dispatch and forwarding (p. 5, p. 6). An intermittent *full* partition of a follower reproduces the repeated elections of the Cloudflare outage (p. 6). With PreVote enabled there are no leader elections during the partial partition nor afterwards (Fig. 9, p. 6), but requests sent to the isolated node remain delayed (p. 6).
- **Relevance:** RQ1 (partial-connectivity model; emulation); RQ2 (PreVote and CheckQuorum affect availability only).
- **Limitations:** One three-node scenario family; one etcd version; the paper does not claim a general liveness result for PreVote/CheckQuorum.
- **Extraction confidence:** high

### kettaneh2026
- **Full reference:** I. Kettaneh, T. Radeva, A. Ajmani et al. "Scalable Leader Leases For Multi Consensus Groups in CockroachDB." ACM, 2026. doi:10.1145/3788853.3803081
- **Communication model:** Crash failures plus symmetric and asymmetric network faults, detected per directed edge by the Liveness Fabric (p. 1, p. 4). Evaluation injects node crash, full partition, partial partition and disk stall (p. 10).
- **Properties analysed:** safety (lease disjointness, Theorem 4.7, p. 9); availability (failover time); CPU overhead and scalability.
- **Method:** protocol design in production (CockroachDB); invariants with proof sketches (Lemmas 4.2–4.5, p. 9); TLA+ verification of Liveness Fabric properties (p. 8); testbed evaluation.
- **Raft mechanisms and timing/clock assumptions as stated:** Leader fortification: followers promise not to campaign or vote "until their clocks exceed a specific timestamp" (p. 5). Liveness Fabric support is granted "until B's clock time exceeds timestamp X" (p. 4). The scheme "relies only on monotonic clocks at each node, and not on clock synchronization"; messages carry the sender's HLC timestamp, which updates the receiver's clock "and provide[s] a causality guarantee and rough clock synchronization" (p. 7). Under clock skew, support "ends at a timestamp on which both n and n′ agree, although in real time the two nodes reach that timestamp at different times" (p. 8). A lease is an interval of timestamps [t1, t2) (Definition 4.6, p. 9); a newly elected leader's HLC exceeds the previous leader's maximum support expiry because vote responses carry timestamps (Lemma 4.5, p. 9). Clock synchronization for linearizability is handled by HLC uncertainty intervals in the transaction layer and is "not within the purview of this paper" (p. 3). They describe Raft's thesis lease as one whose "correctness depends on a bound on clock drift" (p. 12).
- **Physical parameters:** support expiration about 3 s ahead; heartbeats every 1 s (p. 8). No distances, velocities or clock classes.
- **Key results:** Lease disjointness holds over HLC timestamps (Theorem 4.7, p. 9). Failover: Leader Leases recover in 4.0–4.7 s median and 6.5 s p99 after crash or full partition; 4.3 s median and 5.8 s p99 under partial partition; centralized leases do not recover under partial partition (p. 10).
- **Relevance:** RQ2 (production Raft lease); RQ4 (lease safety is stated in a timestamp domain with causal propagation of clock values, not as bounded drift against real time; real-time consistency is delegated to a separate layer). This is the closest the corpus comes to a frame-free formulation of lease safety, but it does not analyse physical or relativistic time.
- **Limitations:** Proofs are sketches; the mapping from timestamp disjointness to real-time linearizability is outside the paper (p. 3). Industry companion paper; the PDF is the Cockroach Labs copy.
- **Extraction confidence:** high

### li2023
- **Full reference:** Y. Li, Y. Fan, L. Zhang, J. Crowcroft. "RAFT Consensus Reliability in Wireless Networks: Probabilistic Analysis." IEEE Internet of Things Journal, 2023. doi:10.1109/JIOT.2023.3257402
- **Communication model:** Probabilistic node crash and communication-link failure (downlink leader→follower, uplink follower→leader), motivated by wireless fading and jamming (pp. 3–4). Delay and throughput are explicitly not modelled (p. 11).
- **Properties analysed:** "consensus reliability" (probability that a log-replication round reaches consensus); not latency.
- **Method:** analytical (Markov-property failure model; p.d.f. and mean of consensus reliability) with simulation (p. 4, Section VI).
- **Raft mechanisms and timing/clock assumptions as stated:** Log replication rounds (the model is "for the log replication", p. 11); no timeout or clock assumptions.
- **Physical parameters:** not reported (link and node reliabilities as probabilities).
- **Key results:** Defines Reliability Gain and Tolerance Gain, linear relations between consensus reliability and joint failure rate and fault threshold; each deterministically failed node raises the order of magnitude of consensus failure rate linearly (p. 4).
- **Relevance:** RQ1 (probabilistic link-failure model for Raft; analytical method).
- **Limitations:** No timing; independence assumptions; replication rounds only, not elections.
- **Extraction confidence:** medium (results extracted from the contribution summary; derivations not checked)

### li2026
- **Full reference:** Y. Li, Z. Xu, Z. Zhou et al. "Distributed Consensus Network: A Modularized Communication Framework and Reliability Probabilistic Analysis." IEEE Transactions on Networking, 2026. doi:10.1109/TON.2026.3667834
- **Communication model:** Link loss and node failure as probabilities, motivated by wireless fading and jamming; modular communication components that compose RAFT, single-decree Paxos, PBFT and HotStuff (p. 1).
- **Properties analysed:** consensus reliability (failure rate) and commit latency.
- **Method:** analytical (probabilistic, per communication component) and an implemented Raft system for verification (p. 1, p. 2).
- **Raft mechanisms and timing/clock assumptions as stated:** log replication rounds; no clock assumptions reported.
- **Physical parameters:** example: single-link latency 0.1 s, arrival rate 60 per second, 6 followers and 1 leader with 2 followers crashed (Fig. 1, p. 2).
- **Key results:** A small drop in link quality (loss rate 0 to 0.05) "could greatly increase the latency" of Raft in the example (Fig. 1, p. 1–2); higher consensus failure rate causes higher latency; two latency optimisations are proposed and verified on the implementation (p. 2).
- **Relevance:** RQ1 (probabilistic loss model covering Raft and other protocols).
- **Limitations:** Loss probabilities assumed independent; no timing-assumption analysis. The PDF is the arXiv preprint 2502.12069 (published in IEEE/ACM Trans. Networking 2026).
- **Extraction confidence:** medium (key results taken from introduction and figure; later sections not checked)

### li2026a
- **Full reference:** J. Li, R. Huang, N. Shi et al. "Satellite Network-Optimized Dynamic Scoped Hierarchical Raft for Blockchain Consensus." Autonomous Intelligent Systems, 2026. doi:10.1007/s43684-026-00126-3
- **Communication model:** Satellite-network motivation (bandwidth limits, signal delays, instability, p. 1); experiments on cloud servers and VMs with simulated WAN latency 50–2000 ms RTT and 50–200 Mbps per link (Table 2, p. 9); node disconnection scenarios with heterogeneous "network performance scores" (p. 10).
- **Properties analysed:** throughput, transaction latency, leader-election time (availability); safety argued informally.
- **Method:** protocol design (Dynamic Scoped Hierarchical Raft, DSH-Raft) and testbed on Hyperledger Fabric v2.4 (p. 9).
- **Raft mechanisms and timing/clock assumptions as stated:** Leader candidates restricted to a consensus subset chosen by network performance, computing power, historical stability and "satellite window time" (p. 11); Raft's election voting rule retained (p. 8). Safety claim: Raft's safety properties "remain valid"; "Failures and partitions affect only liveness or propagation latency, not safety" (p. 9).
- **Physical parameters:** simulated RTT 50–2000 ms; 4–20 nodes (pp. 9–10). No orbital parameters or clock classes.
- **Key results:** versus Raft: +65% throughput, −12% latency, −71% leader-election time at coefficient of variation 0.5 (p. 1, p. 11).
- **Relevance:** RQ1 (Raft variant evaluated under WAN-scale delay motivated by satellites).
- **Limitations:** Satellite links are not modelled physically (simulated RTT only); safety argument informal; blockchain framing.
- **Extraction confidence:** medium

### liang2024
- **Full reference:** Z. Liang, V. Jabrayilov, A. Charapko, A. Aghayev. "MultiPaxos Made Complete." arXiv, 2024. arXiv:2405.11183
- **Communication model:** Partial network partitions: "leader-losing-quorum" (all peers disconnected from each other except one stable peer) and "leader-churning" (two peers mutually unreachable but connected through a third, as in the Cloudflare incident) (p. 2, p. 8); 20 s partitions in experiments (p. 11).
- **Properties analysed:** availability (normalised throughput) under partial partitions; resource use; safety noted as unaffected by partial partitions (p. 3).
- **Method:** complete MultiPaxos design and implementation; experiments with YCSB against etcd's Raft with and without CheckQuorum (pp. 11–12).
- **Raft mechanisms and timing/clock assumptions as stated:** Heartbeats piggybacked on Commit requests every commit_interval; followers start elections on missed heartbeats (p. 7). Adaptive timeout: peers that participate excessively in elections increase their timeout (p. 2, p. 8). etcd CheckQuorum: leader steps down on losing majority connectivity and followers ignore votes while hearing from a leader (p. 11). Raft's consecutive-log requirement is said, citing prior work, to deadlock under some partial partitions (p. 1).
- **Physical parameters:** not reported beyond partition timing.
- **Key results:** Leader-losing-quorum: MultiPaxos and etcd without CheckQuorum drop to 65–75% and 65–70% and recover once the stable peer is elected; etcd with CheckQuorum varies from about 90% down to below 10% because the stable peer's term can lag (pp. 11–12). Leader-churning: classic MultiPaxos loses nearly 99% of throughput; adaptive-timeout MultiPaxos only 30%; etcd 20–90%; etcd with CheckQuorum is unaffected during the partition but suffers several election rounds after it heals (p. 12).
- **Relevance:** RQ1 (partial-connectivity model; testbed); RQ2 (CheckQuorum and timeout adaptation affect availability, with outcomes that depend on the partition shape).
- **Limitations:** Preprint; MultiPaxos rather than Raft, though etcd-Raft is measured directly; performance-level, no proofs.
- **Extraction confidence:** high

### luo2023
- **Full reference:** H. Luo, X. Yang, H. Yu et al. "Performance Analysis and Comparison of Non-ideal Wireless PBFT and RAFT Consensus Networks in 6G Communications." arXiv, 2023. arXiv:2304.08697
- **Communication model:** Wireless physical layer: Rayleigh fading and close-in free-space reference-distance path loss, for THz and mmWave signals (p. 1, p. 2). Nodes separated by distance; transmission success depends on SINR.
- **Properties analysed:** consensus success rate, latency, throughput, reliability gain (log of success rate), energy consumption (p. 1).
- **Method:** analytical derivation with numerical simulation (pp. 2, 12).
- **Raft mechanisms and timing/clock assumptions as stated:** Raft's voting-based replication; tolerates (n−1)/2 failed nodes (p. 1). No timeout or clock assumptions extracted.
- **Physical parameters:** mmWave 26.5–100 GHz, THz 0.1–10 THz (p. 2); simulated networks of 4, 7, 10 and 13 nodes (p. 12). Defines an "active distance": the maximum node separation below which consensus inevitably succeeds (p. 2, p. 12).
- **Key results:** Relationship between node count and reliability gain is "Gaussian-like" (p. 2). Raft consumes less energy than PBFT, attributed to its simpler communication flow and shorter latency; THz energy two orders of magnitude lower than mmWave in their setting (p. 12).
- **Relevance:** RQ1 (Raft under a physical-layer channel model with distance dependence).
- **Limitations:** The arXiv PDF has no usable text layer; extraction from rendered pages 1, 2, 12, 13 only; blockchain framing; success defined per consensus round.
- **Extraction confidence:** low (only four pages read)

### mason2026
- **Full reference:** T. Mason. "Legible Consensus: Topology-Aware Quorum Geometry for Asymmetric Networks." arXiv, 2026. arXiv:2603.28788
- **Communication model:** Physically tiered network (Earth 5, LEO 1, Moon 1, Mars 3 nodes) with speed-of-light latencies; Mars conjunction blackout; sparse vs full-coverage ground-station visibility (pp. 1–2). Discrete-event Paxos simulator (Eidolon) (p. 2).
- **Properties analysed:** safety (quorum intersection) and liveness (which tiers retain Phase 1 capability); consensus latency; crash tolerance.
- **Method:** quorum-system design (crumbling walls mapped to tiers, Flexible-Paxos-style phase quorums); exhaustive TLA+ verification of intersection; simulation (pp. 1–2).
- **Raft mechanisms and timing/clock assumptions as stated:** Multi-Paxos leader election (Phase 1) and commit (Phase 2 = Earth row) (p. 2). The conflation error in flat quorums "exists at terrestrial scales but is masked by generous timeouts" (p. 2). No clock-rate model.
- **Physical parameters:** Earth–Mars distance up to 22 light-minutes (p. 2); per-tier consensus latency equals the light round-trip to Earth: 183 ms (Earth), 131 ms (LEO), 5.1 s (Moon) (p. 1).
- **Key results:** During Mars conjunction only the Mars tier loses global Phase 1 capability (p. 1); sparse LEO visibility of 3 of 5 ground stations breaks LEO liveness although the wall permits it (p. 2); under two Earth crashes the topology-aware construction keeps 98% success vs below 50% for the flat local one (p. 2); Earth has 4.6× more valid Phase 1 quorums than Mars (p. 2).
- **Relevance:** RQ1 (light-time delay and blackout model for leader-based consensus; results transfer to Raft-like leader election via quorum structure).
- **Limitations:** "All results are design-level" (p. 1); Paxos rather than Raft; relativistic clock effects not modelled; preprint.
- **Extraction confidence:** high

### matherat2003
- **Full reference:** P. Matherat, M. Jaekel. "Concurrent Computing Machines and Physical Space-Time." 2003. doi:10.1017/S0960129503004067
- **Communication model:** Physical signal propagation in logic circuits; relativistic definition of time via clocks and exchanged light signals, simultaneity being "a construction, or clock synchronization" (p. 3).
- **Properties analysed:** correctness of logical operations under propagation delays ("computing interferences", p. 1, p. 14). No protocol safety or liveness.
- **Method:** conceptual analysis with graphical (spacetime-style) representation; survey of methods for handling interferences.
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable. Synchronous circuits: a single clock "provides a global reference to a Newtonian time" (p. 14).
- **Physical parameters:** not reported.
- **Key results:** "Synchronous circuits rely on time simultaneity classes, and thus on a causal structure which is typical of Newtonian space-time. Asynchronous circuits ... characterizes relativistic space-time" (paraphrase of p. 14); delay-insensitive circuits sit between the two (p. 14).
- **Relevance:** RQ3 (conceptual precursor linking asynchrony with relativistic causal structure, at the hardware level).
- **Limitations:** Circuits rather than message-passing distributed systems; no formal theorem. The PDF is the arXiv preprint cs/0112020 (published in Math. Struct. in Comp. Science).
- **Extraction confidence:** medium (qualitative paper; main claim located on p. 14)

### matherat2011
- **Full reference:** P. Matherat, M. Jaekel. "Relativistic Causality and Clockless Circuits." 2011. doi:10.1145/2043643.2043650
- **Communication model:** Relativistic spacetime: events separated by time-like, light-like or space-like intervals; the time order of space-like separated events is observer-dependent (p. 5). Communication between delay-insensitive (DI) components and their environment.
- **Properties analysed:** correct specification of DI components (Udding's rules) under partial time order.
- **Method:** formal (trace theory generalised to relativistic traces, "R-traces").
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable. Clockless (delay-insensitive) circuits.
- **Physical parameters:** not reported.
- **Key results:** Udding's rules rewritten in terms of R-traces, exhibiting "their intrinsic relation with relativistic causality" (p. 1, p. 23). R-traces map to pairs of classical traces when propagation is "totally controlled" (classical spacetime, pp. 21–22). "Relativistic time can only satisfy a partial ordering to remain compatible with observer-dependent propagation delays" (p. 22).
- **Relevance:** RQ3 (formal model of computation compatible with relativistic causality, at circuit level).
- **Limitations:** Hardware components rather than message-passing processes; no fault model; no clock-dependent mechanisms. The PDF is the arXiv preprint 1112.5200.
- **Extraction confidence:** medium

### mattern1992
- **Full reference:** F. Mattern. "On the Relativistic Structure of Logical Time in Distributed Systems." Parallel and Distributed Algorithms, 1992. url:https://vs.inf.ethz.ch/publ/papers/relativistic_time.pdf
- **Communication model:** Asynchronous message passing: "message transmission times are unpredictable" and processes have no global clock or perfectly synchronised local clocks (p. 1).
- **Properties analysed:** structure of logical (vector) time; consistent cuts and global states. No safety or liveness of a protocol.
- **Method:** mathematical (order theory; vector time as a lattice); analogy with Minkowski spacetime (pp. 18–21).
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable (no Raft). Assumes no global or perfectly synchronised clocks (p. 1).
- **Physical parameters:** not reported (light-cone relation stated with maximum speed c, normalised to 1, p. 20).
- **Key results:** Vector time is a partially ordered lattice isomorphic to the causality structure (p. 1). Mutually independent events are exactly those that "happen simultaneously" in vector time (p. 18). Because of bounded signal speed "real time is not linearly ordered but merely a partial order just like vector time" (p. 18). Causality-preserving "rubber band" transformations of time diagrams correspond to Lorentz transformations (p. 20). For two processes, vector-time order and light-cone order are "basically identical" (p. 20). Vector time "might be the correct model of time for distributed systems" (p. 21).
- **Relevance:** RQ3 (origin of the analogy between causal order in distributed computations and Minkowski causal structure).
- **Limitations:** Analogy, not a physical model of computation; no clocks measuring proper time, no protocol correctness. The paper states it is based on the author's earlier papers, including "Virtual Time and Global States of Distributed Systems" (p. 1).
- **Extraction confidence:** high (text layer has OCR-like spacing artefacts; content unambiguous)

### messerschmitt2023
- **Full reference:** D. Messerschmitt, I. Morrison, T. Mozdzen, P. Lubin. "Timing Relationships and Resulting Communications Challenges in Relativistic Travel." 2023. doi:10.1016/B978-0-323-91280-8.00012-5
- **Communication model:** Photon-based messaging between an origin O and a destination D at rest in a common inertial frame and a spacecraft C with constant self-acceleration or an accelerate–decelerate "launch-landing" trajectory (p. 1). Each participant measures its own proper ("traveler's") time (p. 3). Responses are assumed immediate (p. 5).
- **Properties analysed:** timing relationships only: clock images (mapping transmit to receive clock readings), query–response latency, time warping of streams, communication blackouts (p. 1).
- **Method:** analytical (special relativity; closed-form trajectories), illustrated with mission scenarios.
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable. The clock image Ψ_{A⇒B} maps A's emission time to B's detection time and is "determined by kinematic variables" (p. 4). Query–response latency is the composition of clock images Ψ_{B⇒A} ∘ Ψ_{A⇒B}, measured on A's local clock (p. 6).
- **Physical parameters:** 1-g self-acceleration, event horizon t_H = 0.97 yr (Fig. 3, p. 13); distances in light years (p. 13); a wide range of O–D separations (p. 1).
- **Key results:** Large query–response latency, except shortly after launch or before landing, "is a severe limit on remote control and social interaction"; when photons travel in the spacecraft's direction, blackouts restrict one- and two-way communication (p. 1). For an indefinitely accelerating spacecraft, emissions from the origin after t_H never reach it (p. 13). Productive communication windows differ strongly by direction (p. 15).
- **Relevance:** RQ3 (quantified relativistic timekeeping between communicating nodes); RQ4 (a round-trip timeout on one node's proper time as a function of trajectory, the quantity a lease or election timer would use, though the paper does not model any protocol).
- **Limitations:** No distributed-coordination protocol or fault model; extreme (interstellar) regime. The PDF is the arXiv preprint; the published version is a 2024 Elsevier book chapter (DOI 10.1016/B978-0-323-91280-8.00012-5).
- **Extraction confidence:** medium (long analytical paper; only the framework and headline results extracted)

### naser-pastoriza2023
- **Full reference:** A. Naser-Pastoriza, G. Chockler, A. Gotsman. "Fault-Tolerant Computing with Unreliable Channels (Extended Version)." arXiv, 2023. arXiv:2305.15150
- **Communication model:** Process crashes plus channel failures: correct channels eventually reliable, faulty channels "flaky", able to drop any message with no fairness guarantee; covers indirect, asymmetric and intermittent connectivity (pp. 1–3). Asynchrony for registers; partial synchrony (asynchronous period, then synchronous) for consensus (p. 3).
- **Properties analysed:** solvability (safety and wait-free or obstruction-free termination) of registers and consensus.
- **Method:** proofs: lower bounds on connectivity and matching algorithms (a view-synchronizer-based consensus) (p. 1, p. 3).
- **Raft mechanisms and timing/clock assumptions as stated:** Standard solutions based on leader oracles and failure detectors are ruled out under flaky channels, since they may fail to identify processes with reliable connectivity (p. 1, p. 2). Consensus uses partial synchrony (p. 3).
- **Physical parameters:** not applicable.
- **Key results:** For any n-process register or consensus implementation, processes where obstruction-freedom holds must be strongly connected by correct channels; with n = 2k + 1 and k crashes, they must belong to a set of at least k + 1 correct processes strongly connected by correct channels (the "connected core") (p. 3). This generalises CAP (p. 3). Matching algorithms guarantee wait-freedom at all core members under flaky faulty channels (p. 3).
- **Relevance:** RQ1 (which channel failures consensus tolerates; partially synchronous model); RQ2 (why leader-election/failure-detector designs such as Raft's can lose liveness under flaky links).
- **Limitations:** Not Raft-specific; the algorithm is not leader-based. The PDF is the arXiv extended version (conference version at OPODIS 2023 per Semantic Scholar).
- **Extraction confidence:** high

### naser-pastoriza2025
- **Full reference:** A. Naser-Pastoriza, G. Chockler, A. Gotsman, F. Ryabinin. "Tight Bounds on Channel Reliability via Generalized Quorum Systems." ACM, 2025. doi:10.1145/3732772.3733529
- **Communication model:** Arbitrary patterns of process and channel failures over unidirectional channels (a fail-prone system) (p. 1, p. 2); consensus under partial synchrony (p. 2).
- **Properties analysed:** solvability (tight bounds) of atomic registers, atomic snapshots, lattice agreement and consensus.
- **Method:** proofs: generalised quorum systems (GQS), upper bounds by construction, lower bounds via lattice agreement (p. 2).
- **Raft mechanisms and timing/clock assumptions as stated:** not Raft-specific; classical read-write quorum systems enable ABD and Paxos (p. 1). Consensus assumes partial synchrony (p. 2).
- **Physical parameters:** not applicable.
- **Key results:** Registers, snapshots, lattice agreement and partially synchronous consensus are implementable "even when none of the available read quorums is strongly connected by correct channels", if some strongly connected write quorum is unidirectionally reachable from some read quorum (p. 2). The existence of a GQS is a tight bound on connectivity for partially synchronous consensus (p. 2).
- **Relevance:** RQ1 (tight characterisation of tolerable channel failures, including asymmetric connectivity).
- **Limitations:** Not leader-based SMR specifically; transfer to Raft requires protocol changes. The PDF is the arXiv extended version 2505.02646 (PODC 2025 version exists).
- **Extraction confidence:** high

### ongaro2014
- **Full reference:** D. Ongaro. "Consensus: Bridging Theory and Practice." Stanford University, 2014. url:https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf
- **Communication model:** Safety proof: asynchronous, no notion of time; messages take arbitrary steps to arrive; network may reorder, drop and duplicate; servers crash-stop and may restart from stable storage (p. 130). Liveness/availability: timing requirement broadcastTime ≪ electionTimeout ≪ MTBF (p. 45). Election evaluation: fixed and variable one-way latency models (Ch. 9), real LAN (gigabit Ethernet, p. 150) and simulated WAN with one-way latency 30–40 ms (AvailSim, pp. 153–154).
- **Properties analysed:** safety (State Machine Safety, TLA+ spec and hand proof, pp. 130–131); availability/liveness and election latency (Ch. 9); linearizable reads (Ch. 6).
- **Method:** formal specification (TLA+) with proof; analytical election model; testbed (LogCabin, LAN); simulation (AvailSim, WAN).
- **Raft mechanisms and timing/clock assumptions as stated:** "safety must not depend on timing"; availability "must inevitably depend on timing" (p. 45). Timing requirement broadcastTime ≪ electionTimeout ≪ MTBF (pp. 45–46). Randomised election timeouts; recommended 150–300 ms (p. 152). Leader steps down if an election timeout elapses without a successful round of heartbeats to a majority (p. 87). Votes ignored within the minimum election timeout of hearing from a current leader (p. 60). Pre-Vote (pp. 58–59, 155). ReadIndex reads: one round of heartbeats to a majority, no clock (p. 91). Lease-based reads: lease extends to start + election timeout / clock drift bound; "assumes a bound on clock drift across servers (over a given time period, no server's clock increases more than this bound times any other)"; if violated, "the system could return arbitrarily stale information"; LogCabin does not implement it and it is not recommended unless needed (p. 92).
- **Physical parameters:** broadcast time 0.5–20 ms, election timeout 10–500 ms, MTBF months (p. 46); WAN one-way latency 30–40 ms (p. 154). No distances, velocities or clock classes.
- **Key results:** With 5 ms of randomness median downtime 287 ms; 12–24 ms timeouts give 35 ms average election but going lower violates the timing requirement (p. 152). Timeout range of about ten times one-way latency recommended (p. 150). WAN: with one of five servers failed, average election about 475 ms and 99.9% within 1.5 s; with two failed about 650 ms and 3 s (p. 154). Pre-Vote prevents a rejoining partitioned server from disrupting the cluster (p. 155), but does not stop all disruptive-server cases during membership change (p. 59). Open questions listed: asymmetric networks, severe packet loss, severe clock drift (p. 155).
- **Relevance:** RQ1 (asynchronous safety proof, partially synchronous timing requirement); RQ2 (primary source for all timing-dependent mechanisms; lease is the only one whose correctness rests on a clock-drift bound); RQ4 (drift bound stated relative to other servers' clocks, no physical time model).
- **Limitations:** Election evaluation assumes symmetric latency, no packet loss, no clock drift (open questions, p. 155). The lease is described, not proved. PDF page numbers differ from printed numbers by 18.
- **Extraction confidence:** high

### ongaro2014a
- **Full reference:** D. Ongaro, J. Ousterhout. "In Search of an Understandable Consensus Algorithm." Proceedings of the 2014 USENIX Annual Technical Conference (USENIX ATC 14), 2014. url:https://www.usenix.org/conference/atc14/technical-sessions/presentation/ongaro
- **Communication model:** Servers crash-stop and may recover; safety independent of timing: "faulty clocks and extreme message delays can, at worst, cause availability problems" (p. 3). Availability requires broadcastTime ≪ electionTimeout ≪ MTBF (p. 10). Evaluation on a real cluster; the network is not otherwise parameterised.
- **Properties analysed:** safety (argued; formal proof referenced), availability/leader-election latency.
- **Method:** algorithm design; implementation and testbed measurement (Fig. 14, p. 14); user study (not relevant here).
- **Raft mechanisms and timing/clock assumptions as stated:** Terms act as a logical clock; "Raft ensures that there is at most one leader in a given term" (p. 6). Randomised election timeouts, for example 150–300 ms (p. 7). Timing requirement broadcastTime ≪ electionTimeout ≪ MTBF (p. 10). Servers ignore RequestVote within the minimum election timeout of hearing from a current leader (p. 12). Client interaction and linearizable reads, and so leases, are omitted and deferred to the extended version (p. 12).
- **Physical parameters:** not reported, apart from timeout values.
- **Key results:** 5 ms of randomness gives median downtime 287 ms; 50 ms worst case 513 ms over 1000 trials; 12–24 ms timeouts give 35 ms average election; lower timeouts violate the timing requirement; 150–300 ms recommended (p. 14).
- **Relevance:** RQ1 (safety time-independent); RQ2 (election timeout and heartbeat affect availability only).
- **Limitations:** Leases and read handling are not in this paper (p. 12); the network model is not varied beyond timeout ranges.
- **Extraction confidence:** high

### sakic2019
- **Full reference:** E. Sakic, W. Kellerer. "Response Time and Availability Study of RAFT Consensus in Distributed SDN Control Plane." 2019. doi:10.1109/TNSM.2017.2775061
- **Communication model:** "reliable event delivery and bounded network, application and data-store commit delays"; failures as stochastic arrivals (long term) or deterministic occurrences (worst case) (p. 2). Controller-to-controller delays depend on placement (p. 4).
- **Properties analysed:** response time (with probabilistic guarantees) and availability of a Raft-replicated SDN controller cluster.
- **Method:** analytical: Stochastic Activity Networks compiled to CTMCs, parametrised from real-world experiments (p. 1, p. 2).
- **Raft mechanisms and timing/clock assumptions as stated:** Follower, candidate and election timeouts modelled as recovery delays; recovery takes "a non-deterministic period" depending on candidate and election timeouts (pp. 4–5, p. 7–8).
- **Physical parameters:** cluster sizes of 3–5 up to about 20 controllers (p. 13). No clock parameters.
- **Key results:** Assuming a balanced distribution of controllers with respect to controller-to-controller delay, larger clusters give lower worst-case response times and higher availability; a watchdog for fast recovery from software failures improves short-term response time and long-term availability (p. 13).
- **Relevance:** RQ1 (bounded-delay, stochastic-failure analytical model of Raft).
- **Limitations:** Assumes reliable delivery (no loss); SDN-specific parametrisation. The PDF is the arXiv version 1902.02537 (published in IEEE TNSM).
- **Extraction confidence:** high

### salimnejad2024
- **Full reference:** M. Salimnejad, N. Pappas, M. Kountouris. "So Timely, Yet So Stale: The Impact of Clock Drift in Real-Time Systems." 2024. doi:10.1109/LCOMM.2025.3590865
- **Communication model:** Slotted time; transmitter sends status updates over an unreliable channel with success probability p_s (p. 2). No global clock: transmitter and receiver have separate local clocks with drift between them (p. 2).
- **Properties analysed:** information freshness (Age of Information, AoI). No safety or liveness.
- **Method:** analytical (closed-form AoI distributions) with numerical results.
- **Raft mechanisms and timing/clock assumptions as stated:** not applicable. Drift models: deterministic constant drift of d slots per slot; probabilistic drift of k ∈ {0..K} slots (categorical); and drift in {−1, 0, +1} (p. 2). Clock drift "can also naturally arise due to time dilation and other relativistic effects" (p. 1, motivation only).
- **Physical parameters:** not reported (drift in slots).
- **Key results:** Average AoI with deterministic drift d is (d + 1)/p_s (Lemma 1, p. 2); closed forms for probabilistic drift (pp. 2–4).
- **Relevance:** RQ3 and RQ4 (a two-clock model in which timestamps from different clocks are compared); relativistic origin of drift is mentioned but not modelled.
- **Limitations:** Two nodes, no coordination protocol, abstract drift units. The PDF is the arXiv preprint (published in IEEE Commun. Lett. 2025).
- **Extraction confidence:** high

### shiozaki2025
- **Full reference:** K. Shiozaki, J. Nakamura. "Dynamic Tuning of Election Parameters for Timely Leader Failover in State Machine Replication." 2025. doi:10.1109/ACCESS.2026.3724865
- **Communication model:** Crash-recovery servers; messages "may be delayed, lost, duplicated, or reordered, but ... not corrupted"; no clock synchronisation and no bounded message delays assumed (p. 4). Fluctuating RTT and packet-loss rate (p. 2); evaluation with emulated RTT changes, for example 50 ms to 500 ms (p. 13).
- **Properties analysed:** availability: failure-detection time and out-of-service (OTS) time during leader failover; throughput.
- **Method:** analysis of parameter conditions; implementation (Dynatune) on etcd (Raft) and JPaxos (Multi-Paxos); experiments.
- **Raft mechanisms and timing/clock assumptions as stated:** Heartbeat interval and election timeout tuned from RTT and loss measured via heartbeats (p. 2). RTT measurement "relies only on the leader's local clock ... without assuming clock synchronization across servers" (p. 6). Liveness requires weak assumptions "such as finite bounds on clock drift and message delays", as in Raft and Multi-Paxos (p. 5). Safety unchanged because only heartbeats are extended (p. 2).
- **Physical parameters:** RTT 50–500 ms in experiments (p. 13); NTP-synchronised machines with errors of "several tens of milliseconds" in one measurement set (p. 11). No distances or velocities.
- **Key results:** On Raft, mean detection time falls 78% (1171 → 258 ms) and OTS time 45% (1420 → 777 ms) (p. 7); on Multi-Paxos 79% and 75% (p. 1). Without pre-vote one unnecessary election occurs during an RTT jump (p. 13).
- **Relevance:** RQ1 (variable-delay, lossy WAN model); RQ2 (election timeout and heartbeat affect availability; liveness stated to need bounded drift and delay).
- **Limitations:** Parameters derived from measured conditions; clock-drift bound only cited as a liveness assumption, not analysed. The retrieved PDF carries the IEEE Access 2026 header.
- **Extraction confidence:** high

### tennage2023
- **Full reference:** P. Tennage, C. Basescu, L. Kokoris-Kogias et al. "QuePaxa: Escaping the Tyranny of Timeouts in Consensus." ACM, 2023. doi:10.1145/3600006.3613150
- **Communication model:** Asynchronous crash-stop model for the consensus core (liveness without timing assumptions, using randomisation to circumvent FLP); adverse conditions include DoS attacks, misconfiguration and slow leaders; LAN and WAN experiments (p. 1).
- **Properties analysed:** liveness under adverse networks; throughput and latency.
- **Method:** protocol design (QuePaxa) with implementation and LAN/WAN experiments (p. 1).
- **Raft mechanisms and timing/clock assumptions as stated:** Leader-driven protocols "rely on partial-synchrony assumptions and timeout-triggered view changes for availability, and may lose liveness under adverse network conditions"; timeouts must be conservatively large and require manual configuration (the "tyranny of timeouts", p. 1). QuePaxa replaces timeouts with short hedging delays and a one-round-trip fast path comparable to Multi-Paxos or Raft (p. 1).
- **Physical parameters:** not reported beyond LAN/WAN deployment.
- **Key results:** Normal-case throughput 584k (LAN) and 250k (WAN) cmd/s, comparable to Multi-Paxos; under DoS, misconfiguration or slow leaders QuePaxa remains live with median latency under 380 ms in WAN experiments (p. 1).
- **Relevance:** RQ1 (asynchronous alternative whose liveness does not rest on timeouts); RQ2 (explicit critique of timeout dependence).
- **Limitations:** Randomised consensus rather than Raft; the PDF is the UCL repository copy of the SOSP 2023 paper.
- **Extraction confidence:** high

### tennage2025
- **Full reference:** P. Tennage, A. Desjardins, L. Kokoris-Kogias. "RACS-SADL: Robust and Understandable Randomized Consensus in the Cloud." IEEE, 2025. doi:10.1109/cloud67622.2025.00044
- **Communication model:** Cloud networks with disruptions: partitions, high-loss links, configuration errors ("adversarial network conditions") versus synchronous conditions (p. 1).
- **Properties analysed:** liveness and performance (throughput, latency) under adversarial conditions.
- **Method:** protocol design (RACS, randomised consensus with a Raft-inspired design; SADL-RACS) and prototype on Amazon EC2 (p. 1).
- **Raft mechanisms and timing/clock assumptions as stated:** Leader-based protocols detect adversarial conditions "using timeouts"; timeout-triggered leader election requires a view-change subroutine during which no commands commit (p. 1).
- **Physical parameters:** not reported beyond EC2 deployment.
- **Key results:** Under adversarial conditions RACS reaches 28k cmd/s, "ninefold higher than Raft"; under synchronous conditions it matches Multi-Paxos and Raft at 200k cmd/s with 300 ms median latency; SADL-RACS reaches 500k cmd/s, 150% higher than Raft (p. 1).
- **Relevance:** RQ1 (Raft compared under partitions and loss); RQ2 (timeout-based view change as the fragile element).
- **Limitations:** Randomised protocol, not Raft; the PDF is the arXiv preprint 2404.04183 ("RACS and SADL"), published at IEEE CLOUD 2025.
- **Extraction confidence:** high

### trach2021
- **Full reference:** B. Trach, R. Faqeh, O. Oleksenko et al. "T-Lease: A Trusted Lease Primitive for Distributed Systems." 2021. doi:10.1145/3419111.3421273
- **Communication model:** Hosts (one granter, several holders) exchange messages with a bounded maximum delivery delay (TLA+ constant MsgDeliveryMaxDelay, p. 7). Adversary is a privileged attacker in an untrusted host who can set time-source value and frequency, CPU frequency, deliver interrupts and delay messages (p. 1).
- **Properties analysed:** safety (lease invariant under clock manipulation); liveness (holder eventually gets a lease in normal operation) (p. 2); performance and precision.
- **Method:** system design (Intel SGX and TSX); TLA+ specification and model checking (pp. 2, 7); microbenchmarks and three case studies (FaRM failure detector, Paxos Quorum Leases, strongly consistent caching, pp. 6–7).
- **Raft mechanisms and timing/clock assumptions as stated:** Not Raft-specific; a generic lease primitive, applied to Paxos Quorum Leases (p. 6). Lease correctness invariant: "the lease duration at the granter must be a superset of the lease duration at the holder" (p. 2). "Time-based leases require the use of synchronized clocks that have a maximum drift rate of ± Drift"; lease time is padded by +Drift at the granter and −Drift at holders (p. 7). Threat: an attacker who changes clock value or frequency can violate lease correctness (p. 1).
- **Physical parameters:** clock class: x86 Time-Stamp Counter (TSC) as the untrusted timer (p. 2). No distances or velocities.
- **Key results:** Detects TSC tampering; timer overhead up to 5% in most configurations (p. 2). Case studies show that time manipulation at the granter or holder breaks FaRM failover and caching consistency unless T-Lease is used (pp. 6–7).
- **Relevance:** RQ2 (explicit statement of the bounded-drift-rate assumption behind leases); RQ4 (drift bound is between local clocks and a modelled global now, p. 7; adversarial, not physical, rate change).
- **Limitations:** Threat model is adversarial (TEE setting), not physical clock behaviour; not applied to Raft. The PDF is the arXiv preprint (published at SoCC 2020).
- **Extraction confidence:** high

### wang2025
- **Full reference:** Q. Wang. "BALLAST: Bandit-Assisted Learning for Latency-Aware Stable Timeouts in Raft." arXiv, 2025. arXiv:2512.21165
- **Communication model:** Discrete-event simulation with long-tail delay, jitter, loss, correlated bursts, node heterogeneity, and partition/recovery turbulence; LAN and WAN regimes with mid-run regime switches (p. 1, p. 6).
- **Properties analysed:** availability: end-to-end recovery time, unwritable fraction, split-vote rate.
- **Method:** simulation (30 seeds, 95% bootstrap confidence intervals, p. 5); contextual-bandit (LinUCB) timeout selection with safe exploration.
- **Raft mechanisms and timing/clock assumptions as stated:** Randomised election timeouts described as "a simple and effective liveness heuristic" that becomes brittle under long-tail latency (p. 1). "Writable" = a strict majority has recently observed heartbeats from the same leader within a grace window, 150 ms in the main scenario with 50 ms heartbeats and 10 ms ticks (p. 2). No clock-drift model reported.
- **Physical parameters:** N = 5, 7, 9; 60 s simulated time; 50 ms heartbeats (p. 5). No clock or distance parameters.
- **Key results:** Main scenario (Table 1, p. 6): standard randomised timeouts give mean recovery 1100 ms and unwritable fraction 0.359; BALLAST (bandit_safe) 153.8 ms and 0.042; a quantile-decay heuristic and a Dynatune-style baseline reach lower unwritable fractions (0.031) with higher mean recovery. Adaptive timeouts with safety gating "can materially reduce availability loss" in the most adversarial regime (p. 6).
- **Relevance:** RQ1 (non-stationary WAN delay model; simulation); RQ2 (election timeout affects availability only).
- **Limitations:** Simulation only; single-author preprint; no safety analysis.
- **Extraction confidence:** high

### wang2026
- **Full reference:** Y. Wang, Z. Cheng, Y. Dong, Z. Xu. "CD-Raft: Reducing the Latency of Distributed Consensus in Cross-Domain Sites." 2026. doi:10.1109/INFOCOM59046.2026.11571599
- **Communication model:** Two-tier latency: short intra-domain and long cross-domain RTTs; a leader-based write needs two cross-domain RTTs when client and leader are in different domains (p. 1, p. 3); fault tolerance to node downtime and message loss claimed (p. 3). Evaluation on domains Beijing, Shanghai, Guangzhou (p. 7).
- **Properties analysed:** latency (average, write, read, tail); correctness via TLA+ (p. 2).
- **Method:** protocol design (Fast Return; Optimal Global Leader Position); TLA+ specification; prototype with YCSB workloads (pp. 2, 7).
- **Raft mechanisms and timing/clock assumptions as stated:** Leader placement chosen from request distribution and inter-domain latency (p. 3, p. 5); reads use a read index set to the Global Leader's in-domain commit index (p. 5). No clock assumptions reported.
- **Physical parameters:** inter-city deployment (Beijing, Shanghai, Guangzhou, p. 7); no RTT values extracted.
- **Key results:** Versus Raft, average latency −39.81% and tail −49.44% (write-only), −32.90% and −49.24% (balanced) (p. 1); under Load workload average latency −34% to −41% versus four baselines (p. 7).
- **Relevance:** RQ1 (WAN two-tier delay model; low relevance to timing assumptions).
- **Limitations:** Latency optimisation only; network model is a fixed RTT structure. The PDF is the arXiv preprint (INFOCOM 2026 version exists).
- **Extraction confidence:** medium
