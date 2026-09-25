# Systematic review protocol & log — Raft under communication models and physical (relativistic) constraints

Version 1.1 · 2026-09-25 (RQs aligned with the article) · Reporting framework: PRISMA 2020 (adapted for a single-reviewer scoping review in computer science)

## 1. Review questions (identical to paper/main.typ §3)

- **RQ1 (mapping):** Under which communication models have Raft and equivalent protocols been analysed, for which properties (safety, liveness, latency, availability), and with which methods (proof, model checking, analytical model, simulation, testbed)?
- **RQ2 (timing):** Which Raft mechanisms depend on timing or clock assumptions, whether for safety or only for liveness, and how are those assumptions stated?
- **RQ3 (physics):** Which models of distributed computation in relativistic spacetime exist, and which correctness results do they establish for consensus and replicated state machines?
- **RQ4 (gap):** To what extent have clock-dependent mechanisms been analysed under relativistic or otherwise physically grounded models of time?

Scope frame (PICo-style): **Population** = crash-fault leader-based SMR (Raft; Multi-Paxos/VR where results transfer). **Interest** = explicit communication/timing/clock model. **Context** = terrestrial WAN/wireless, space/DTN, special/general relativity.

## 2. Concept blocks

| Block | Terms |
|---|---|
| A — protocol | `raft W/3 (consensus OR protocol OR algorithm)`, `"replicated state machine"`, `"state machine replication"`, `"leader election"` |
| A-noise (NOT) | `polymeri*`, `"chain transfer"`, `"addition-fragmentation"`, `"optical flow"` — "RAFT" collides with RAFT polymerisation chemistry and the RAFT optical-flow network |
| B — comm. model | `"partial synchrony"`, `"partially synchronous"`, `asynchron*`, `"network partition*"`, `"partial connectivity"`, `"omission fault*"`, `"message loss"`, `"packet loss"`, `intermittent*`, `"delay tolerant"`, `"disruption tolerant"`, `wireless`, `satellite*`, `"inter-satellite"`, `interplanetary`, `"deep space"` |
| C — physics/time | `relativ*`, `"special relativity"`, `spacetime`, `"space-time"`, `"light cone"`, `"speed of light"`, `"proper time"`, `"time dilation"`, `minkowski`, `"relativity of simultaneity"` |
| D — timed mechanisms | `lease*`, `"failure detector*"`, `"election timeout*"`, `"clock drift"`, `"clock skew"`, `"bounded clock*"` |

## 3. Database search strings (to run and log hit counts)

### Scopus (TITLE-ABS-KEY)
```
S1  TITLE-ABS-KEY( (raft W/3 (consensus OR protocol OR algorithm)) OR "replicated state machine" )
    AND TITLE-ABS-KEY( "partial synchrony" OR "partially synchronous" OR asynchron* OR "network partition*"
        OR "partial connectivity" OR "omission fault*" OR "message loss" OR "packet loss" OR intermittent*
        OR "delay tolerant" OR "disruption tolerant" OR wireless OR satellite* OR "inter-satellite"
        OR interplanetary OR "deep space" )
    AND NOT TITLE-ABS-KEY( polymeri* OR "chain transfer" OR "addition-fragmentation" OR "optical flow" )
    AND PUBYEAR > 2013 AND ( LIMIT-TO(SUBJAREA,"COMP") OR LIMIT-TO(SUBJAREA,"ENGI") )

S2  TITLE-ABS-KEY( raft W/3 (consensus OR protocol OR algorithm) )
    AND TITLE-ABS-KEY( relativ* OR spacetime OR "space-time" OR "light cone" OR "speed of light" OR "proper time"
        OR "time dilation" OR lease* OR "failure detector*" OR "election timeout*" OR "clock drift" OR "clock skew" )
    AND NOT TITLE-ABS-KEY( polymeri* OR "chain transfer" OR "optical flow" )

S3  TITLE-ABS-KEY( "distributed system*" OR "distributed comput*" OR "distributed algorithm*" OR consensus
        OR linearizab* OR "state machine replication" )
    AND TITLE-ABS-KEY( relativistic OR "special relativity" OR "general relativity" OR "light cone"
        OR "relativity of simultaneity" OR minkowski OR "proper time" )
    AND LIMIT-TO(SUBJAREA,"COMP")

S4  TITLE-ABS-KEY( (consensus OR "state machine replication" OR paxos OR (raft W/3 consensus) OR "leader election")
    AND ("delay tolerant" OR "disruption tolerant" OR interplanetary OR "deep space" OR "inter-satellite"
        OR "satellite constellation" OR "LEO constellation") ) AND PUBYEAR > 2009
```

### Web of Science Core Collection
```
S1  TS=((raft NEAR/3 (consensus OR protocol OR algorithm)) OR "replicated state machine")
    AND TS=("partial synchrony" OR "partially synchronous" OR asynchron* OR "network partition*" OR "partial connectivity"
        OR "omission fault*" OR "message loss" OR "packet loss" OR intermittent* OR "delay tolerant" OR "disruption tolerant"
        OR wireless OR satellite* OR interplanetary OR "deep space")
    NOT TS=(polymeri* OR "chain transfer" OR "optical flow")      Refine: PY=2014-2026; WC=Computer Science*
S2/S3/S4: same Boolean logic, TS= fields, NEAR/3 for W/3.
```

### IEEE Xplore (Command Search, All Metadata)
```
("All Metadata":raft AND "All Metadata":consensus) AND ("All Metadata":"partial synchrony" OR "All Metadata":partition*
 OR "All Metadata":"packet loss" OR "All Metadata":wireless OR "All Metadata":satellite* OR "All Metadata":"delay tolerant"
 OR "All Metadata":lease OR "All Metadata":relativistic) NOT ("All Metadata":polymer*)
```

### ACM Digital Library (Advanced, Abstract field)
```
[Abstract: raft] AND [Abstract: consensus] AND ([Abstract: "partial synchrony"] OR [Abstract: partition*] OR [Abstract: omission]
 OR [Abstract: "packet loss"] OR [Abstract: wireless] OR [Abstract: satellite*] OR [Abstract: lease*] OR [Abstract: relativistic])
[Abstract: relativistic] AND ([Abstract: linearizab*] OR [Abstract: "distributed comput*"] OR [Abstract: consensus])
```

### arXiv (advanced search / API; covers the 2025–2026 preprints most databases miss)
```
cat:cs.DC AND abs:raft AND (abs:partition OR abs:omission OR abs:lease OR abs:clock OR abs:timeout OR abs:satellite OR abs:wireless)
cat:cs.DC AND (abs:relativistic OR abs:"special relativity" OR abs:"light cone" OR abs:"relativity of simultaneity")
```

### dblp (prefix match; `|` = OR)
```
raft consens partition|partial|omission|wireless|satellite|lease|clock|timeout
relativistic distributed|linearizab|consensus
```

### Pre-registered narrowing rules
Apply in order, stop once a string yields ≤ ~300 records; log every step and the count removed.
- **R1.** Fields are title/abstract/keywords only (already built into the strings).
- **R2.** Split S1: keep the model terms (partial synchrony … omission) in S1; move the application terms (wireless, satellite, DTN) into a separate S1-app.
- **R3.** For S1-app only, add `AND NOT TITLE(blockchain OR "smart contract" OR ledger)`, and screen a 10% random sample of what R3 removes to estimate recall loss.
- **R4.** For S1-app only, restrict to PY ≥ 2018.
- **Never** narrow S2 or S3. They are the gap-defining strings and are small by construction. Instead, dedupe them across databases.

## 4. Eligibility criteria

**Include** records that meet all of the following:
- The protocol is Raft, or crash-fault leader-based SMR where the result transfers to Raft, **or** the record is a model of distributed computation in relativistic spacetime.
- The record makes an explicit communication, timing, or clock model part of the analysis. An evaluation on "a LAN" alone doesn't count.
- The record has technical content: a proof, model checking, an analytical model, a simulation, or a testbed.
- Language is English.
- Publication years are 2014–2026 for Raft; any year for foundational models.

**Exclude** records that meet any of the following:
- E1 uses Raft only as a black-box orderer with no analysis of the network model (typical of blockchain application papers).
- E2 covers BFT-only protocols (unless the record is foundational).
- E3 is physics or time-transfer work with no computational model.
- E4 is non-scholarly: vendor docs, blogs, forums, patents. Exception: named expert grey literature, which is logged separately.
- E5 is a duplicate.
- E6 is a low-evidence review.

**Data-extraction fields** (one row per included record):
- communication model;
- properties analysed (safety / liveness / latency / availability);
- method;
- timed mechanisms used by the protocol (leases, clock bounds, stickiness);
- physical parameters (distances, β, clock class);
- key result;
- artifact availability.

**Reviewer-bias control (single reviewer):** re-screen a random 20% sample after ≥ 7 days, blind to the earlier decisions, and report Cohen's κ.

## 5. What was actually run in this pass (identification log)

Direct database access (Scopus/WoS/IEEE/ACM/arXiv API) was **not** available from this environment. The pass used a general web-search engine, which returns ≤ 10 results per query. The results are therefore a **pilot/scoping identification**, not the final PRISMA search. Hit counts for §3 must come from you running the strings. Six of the 16 queries were known-item verification queries (seeded from the repository's `PUBLISHABLE_RESEARCH_PLAN.md`), which biases toward already-known work. That is stated here as a limitation.

| # | Query (web search) | Type | Hits |
|---|---|---|---|
| 1 | Aeini Golab Raft relativistic linearizability arXiv | known-item | 9 |
| 2 | Jayanti "On Interplanetary and Relativistic Distributed Computing" | known-item | 9 |
| 3 | Gilbert Golab "Making sense of relativistic distributed systems" | known-item | 10 |
| 4 | Raft consensus satellite constellation high latency intermittent links | topical | 9 |
| 5 | consensus protocol delay tolerant network interplanetary Paxos Raft space | topical | 9 |
| 6 | Raft liveness partial network partition PreVote CheckQuorum Omni-Paxos | topical | 9 |
| 7 | analytical model Raft leader election time packet loss network delay | topical | 10 |
| 8 | Raft leader lease clock drift linearizability violation bounded clock | topical | 10 |
| 9 | consensus DTN intermittent connectivity replicated state machine space mission | topical | 9 |
| 10 | relativistic clock synchronization distributed algorithms proper time leases | topical | 9 |
| 11 | Messerschmitt "Relativistic timekeeping, motion, and gravity in distributed systems" | known-item | 9 |
| 12 | BALLAST Raft timeouts non-stationary WAN arXiv 2512.21165 | known-item | 9 |
| 13 | Raft consensus wireless UAV vehicular ad hoc performance | topical | 9 |
| 14 | "Raft consensus reliability in wireless networks: probabilistic analysis" | known-item (snowball) | 10 |
| 15 | leases relativity "twin paradox" distributed systems proper time lease safety | topical (novelty check) | 9 |
| 16 | arXiv 2604.08298 asynchronous quantum distributed computing causality | known-item (snowball) | 10 |
| | **Total records identified** | | **149** |

**Other methods (PRISMA "citation searching"):** backward snowballing from Aeini et al. 2026, Jayanti 2025, Ng et al. 2023, the Raft paper/thesis, and the repository plan → 19 records (18 scholarly + 1 expert grey-literature post).

## 6. PRISMA 2020 flow (this pass)

```
Identification  Records via web-search proxy (16 queries) ............ 149
                Removed before screening ................................ 76
                  (non-scholarly pages, blogs, repos, patents, index/listing pages,
                   duplicate records of the same work)
Screening       Unique scholarly records screened (title/abstract) ..... 73
                Excluded ................................................ 39
                  E3 physics/time-transfer w/o computational model ...... 17
                  E1/E2 blockchain-as-orderer or BFT-only ................ 8
                  off-topic (routing, hardware, alt. protocols, quantum) . 13
                  E6 low-evidence review ................................. 1
Included        From searches ........................................... 34
                From citation searching ................................. 19
                TOTAL INCLUDED .......................................... 53
                  Tier 1 (read first) 12 · Tier 2 (read) 28 · Tier 3 (skim/context) 13
```
Full-text eligibility has **not** yet been assessed: "included" means passed title/abstract screening. Expect some Tier 3 records to drop at full text.

## 7. Included records

Tags in the RIS file use the same labels: `tier1..3`, the theme, and `PRISMA:search` / `PRISMA:citation-chasing`. Records marked "authors: verify" have incomplete metadata. In Zotero, use *Add Item by Identifier* (magic wand) with the arXiv ID or URL, then *Merge Items* in the Duplicate Items pane.

| Tier | First author (year) | Title | Theme | Source | Identifier |
|---|---|---|---|---|---|
| 1 | Aeini et al. (2026) | Analyzing Linearizability in Relativistic Distributed Systems | relativistic-DC | search | doi:10.1145/3820355.3820388 |
| 1 | Jayanti (2025) | On Interplanetary and Relativistic Distributed Computing | relativistic-DC | search | doi:10.1145/3732772.3733563 |
| 1 | Gilbert & Golab (2014) | Making Sense of Relativistic Distributed Systems | relativistic-DC | search | doi:10.1007/978-3-662-45174-8_25 |
| 1 | Messerschmitt (2017) | Relativistic Timekeeping, Motion, and Gravity in Distributed Systems | relativistic-timekeeping | search | https://ieeexplore.ieee.org/abstract/document/7982857/ |
| 1 | Ng et al. (2023) | Omni-Paxos: Breaking the Barriers of Partial Connectivity | raft-comm-model | search | doi:10.1145/3552326.3587441 |
| 1 | (authors: verify) (2025) | LeaseGuard: Raft Leases Done Right | timing-clocks | search | arXiv:2512.15659 |
| 1 | Ongaro & Ousterhout (2014) | In Search of an Understandable Consensus Algorithm | foundations, raft-comm-model | citation-chasing | https://www.usenix.org/conference/atc14/technical-sessions/presentation/ongaro |
| 1 | Ongaro (2014) | Consensus: Bridging Theory and Practice | foundations, timing-clocks | citation-chasing | https://web.stanford.edu/~ouster/cgi-bin/papers/OngaroPhD.pdf |
| 1 | Dwork et al. (1988) | Consensus in the Presence of Partial Synchrony | foundations | citation-chasing | doi:10.1145/42282.42283 |
| 1 | Chen et al. (2002) | On the Quality of Service of Failure Detectors | failure-detection | citation-chasing | doi:10.1109/12.980014 |
| 1 | Jensen et al. (2021) | Examining Raft's Behaviour During Partial Network Failures | raft-comm-model | citation-chasing | doi:10.1145/3447851.3458739 |
| 1 | Howard (2020) | Raft does not Guarantee Liveness in the face of Network Faults | raft-comm-model | citation-chasing | https://decentralizedthoughts.github.io/2020-12-12-raft-liveness-full-omission/ |
| 2 | Matherat & Jaekel (2003) | Concurrent computing machines and physical space-time | relativistic-DC | search | arXiv:cs/0112020 |
| 2 | (authors: verify) (?) | A Latency-Tolerant Extension of the Raft Algorithm for Read-Only Operations in Spaceborne Systems | wireless-space, timing-clocks | search | https://ieeexplore.ieee.org/document/11065606/ |
| 2 | Tseng (2016) | Recent Results on Fault-Tolerant Consensus in Message-Passing Networks | foundations | search | arXiv:1608.07923 |
| 2 | Howard (2014) | ARC: Analysis of Raft Consensus | raft-comm-model | search | https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-857.pdf |
| 2 | (authors: verify) (?) | Delay and Loss Rate Analysis of the Log Commitment Process in Raft | raft-comm-model | search | https://ieeexplore.ieee.org/document/10074865/ |
| 2 | Sakic & Kellerer (2018) | Response Time and Availability Study of RAFT Consensus in Distributed SDN Control Plane | raft-comm-model | search | arXiv:1902.02537 |
| 2 | (authors: verify) (?) | On Using Raft Over Networks: Improving Leader Election | raft-comm-model | search | https://www.researchgate.net/publication/358327855_On_using_Raft_over_Networks_Improving_Leader_Election |
| 2 | Huang et al. (2020) | Performance Analysis of the Raft Consensus Algorithm for Private Blockchains | raft-comm-model | search | arXiv:1808.01081 |
| 2 | (authors: verify) (2025) | Dynatune: Dynamic Tuning of Raft Election Parameters Using Network Measurement | failure-detection | search | arXiv:2507.15154 |
| 2 | (authors: verify) (2026) | Legible Consensus: Topology-Aware Quorum Geometry for Asymmetric Networks | raft-comm-model, wireless-space | search | arXiv:2603.28788 |
| 2 | (authors: verify) (2024) | A survey of fault tolerant consensus in wireless networks | wireless-space | search | https://www.sciencedirect.com/science/article/pii/S2667295224000059 |
| 2 | Wang (2025) | BALLAST: Bandit-Assisted Learning for Latency-Aware Stable Timeouts in Raft | failure-detection | search | doi:10.48550/arXiv.2512.21165 |
| 2 | Li et al. (2023) | RAFT Consensus Reliability in Wireless Networks: Probabilistic Analysis | raft-comm-model, wireless-space | search | doi:10.1109/JIOT.2023.3257402 |
| 2 | Li et al. (2026) | Distributed Consensus Network: A Modularized Communication Framework and Reliability Probabilistic Analysis | raft-comm-model | search | doi:10.1109/TON.2026.3667834 |
| 2 | Howard et al. (2015) | Raft Refloated: Do We Have Consensus? | raft-comm-model | search | doi:10.1145/2723872.2723876 |
| 2 | Trach et al. (2020) | T-Lease: A Trusted Lease Primitive for Distributed Systems | timing-clocks | search | arXiv:2101.06485 |
| 2 | Lamport (1978) | Time, Clocks, and the Ordering of Events in a Distributed System | foundations, relativistic-DC | citation-chasing | doi:10.1145/359545.359563 |
| 2 | Fischer et al. (1985) | Impossibility of Distributed Consensus with One Faulty Process | foundations | citation-chasing | doi:10.1145/3149.214121 |
| 2 | Chandra & Toueg (1996) | Unreliable Failure Detectors for Reliable Distributed Systems | failure-detection, foundations | citation-chasing | doi:10.1145/226643.226647 |
| 2 | Hayashibara et al. (2004) | The phi Accrual Failure Detector | failure-detection | citation-chasing | doi:10.1109/RELDIS.2004.1353004 |
| 2 | Gray & Cheriton (1989) | Leases: An Efficient Fault-Tolerant Mechanism for Distributed File Cache Consistency | timing-clocks | citation-chasing | doi:10.1145/74850.74870 |
| 2 | Liskov (1993) | Practical Uses of Synchronized Clocks in Distributed Systems | timing-clocks | citation-chasing | — |
| 2 | Herlihy & Wing (1990) | Linearizability: A Correctness Condition for Concurrent Objects | foundations | citation-chasing | doi:10.1145/78969.78972 |
| 2 | Corbett & et al. (2013) | Spanner: Google's Globally Distributed Database | timing-clocks | citation-chasing | doi:10.1145/2491245 |
| 2 | Ashby (2003) | Relativity in the Global Positioning System | relativistic-timekeeping | citation-chasing | doi:10.12942/lrr-2003-1 |
| 2 | Alquraan et al. (2018) | An Analysis of Network-Partitioning Failures in Cloud Systems | raft-comm-model | citation-chasing | — |
| 2 | Woos et al. (2016) | Planning for Change in a Formal Verification of the Raft Consensus Protocol | foundations | citation-chasing | doi:10.1145/2854065.2854081 |
| 2 | Mattern (1992) | On the Relativistic Structure of Logical Time in Distributed Systems | relativistic-DC | citation-chasing | — |
| 3 | Jayanti & Natarajan (2026) | Asynchronous Quantum Distributed Computing: Causality, Snapshots, and Global Operations | relativistic-DC | search | arXiv:2604.08298 |
| 3 | (authors: verify) (2023) | Timing relationships and resulting communications challenges in relativistic travel | relativistic-timekeeping | search | arXiv:2311.14039 |
| 3 | (authors: verify) (2011) | Relativistic causality and clockless circuits | relativistic-DC | search | arXiv:1112.5200 |
| 3 | (authors: verify) (2025) | So Timely, Yet So Stale: The Impact of Clock Drift in Real-Time Systems | timing-clocks | search | arXiv:2501.00549 |
| 3 | (authors: verify) (2026) | Satellite network-optimized Dynamic Scoped Hierarchical Raft for blockchain consensus | wireless-space | search | doi:10.1007/s43684-026-00126-3 |
| 3 | (authors: verify) (?) | Revisit Raft Consistency Protocol on Private Blockchain System in High Network Latency | raft-comm-model | search | https://www.researchgate.net/publication/352805556 |
| 3 | (authors: verify) (2026) | CD-Raft: Reducing the Latency of Distributed Consensus in Cross-Domain Sites | raft-comm-model | search | arXiv:2603.10555 |
| 3 | (authors: verify) (2018) | Future Architecture of the Interplanetary Internet | wireless-space | search | arXiv:1810.01093 |
| 3 | (authors: verify) (2023) | Performance Analysis and Comparison of Non-ideal Wireless PBFT and RAFT Consensus Networks in 6G Communications | wireless-space | search | arXiv:2304.08697 |
| 3 | (authors: verify) (2024) | Delay/Disruption-Tolerant Networking-based the Integrated Deep-Space Relay Network: State-of-the-Art | wireless-space | search | doi:10.1016/j.adhoc.2023.103307 |
| 3 | Cerf et al. (2007) | Delay-Tolerant Networking Architecture | wireless-space | search | doi:10.17487/RFC4838 |
| 3 | (authors: verify) (2026) | RUBICONe: Wireless RAFT-Unified Behaviors for Intervehicular Cooperative Operations and Negotiations | wireless-space | search | arXiv:2603.18595 |
| 3 | Burleigh et al. (2003) | Delay-Tolerant Networking: An Approach to Interplanetary Internet | wireless-space | citation-chasing | doi:10.1109/MCOM.2003.1204759 |
## 8. Suggested reading order
1. **Frame the classical model:** DLS 1988; Ongaro & Ousterhout 2014; the Ongaro thesis, §§4.2.3, 6.4, 9.
2. **Communication-model failure modes:** Howard 2020 blog; Jensen et al. 2021; Ng et al. 2023; Huang et al. 2020.
3. **Timing and failure detection:** Chen–Toueg–Aguilera 2002; LeaseGuard 2025; Liskov 1993.
4. **Relativistic correctness:** Gilbert & Golab 2014; Jayanti 2025; Aeini et al. 2026 (read its future-work section closely).
5. **Physical magnitudes:** Messerschmitt 2017; Ashby 2003.

## 9. Next steps to complete the systematic search
- Run S1–S4 in Scopus and WoS; run the IEEE, ACM, arXiv, and dblp strings.
- Record raw counts and apply R1–R4 with counts.
- Deduplicate in Zotero, keeping this set as the seed collection so recall can be checked: every Tier 1 record should reappear in the database results, and any that don't reveal gaps in the strings.
- Forward citation-chase Gilbert & Golab 2014, Jayanti 2025, and Aeini et al. 2026 in Google Scholar/Scopus ("cited by"). This is the highest-yield step for the relativistic strand, which is small.

## 10. Forward snowballing (Litmaps), per Wohlin 2014

Seeds for **complete** forward screening: Gilbert & Golab 2014; Jayanti 2025; Aeini et al. 2026; Messerschmitt 2017; Matherat & Jaekel 2003; Mattern 1992; Jensen, Howard & Mortier 2021; Ng, Haridi & Carbone 2023; LeaseGuard 2025.

**Not seeded**, because they are too highly cited to screen completely: Raft (paper and thesis), FLP, DLS, Lamport 1978, Herlihy & Wing, Spanner, Chandra & Toueg. These are covered by the database strings instead.

**Procedure:**
- For each seed, record the number of citing works, screen them with the §4 criteria in `screening.csv` (source = `forward:<seed>`), and repeat on newly included papers until an iteration adds nothing.
- Report the number of iterations and the records added under "citation searching" in the PRISMA flow.
