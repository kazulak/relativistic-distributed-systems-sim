// Raft under physical communication models: a structured literature survey
// Build: typst compile paper/main.typ   |   live: typst watch paper/main.typ
// refs.bib is auto-exported by Better BibTeX from the Zotero collection "Raft".

#set document(title: "Raft under Physical Communication Models", author: "Tomasz Kazulak")
#set page(paper: "a4", margin: (x: 2.4cm, y: 2.6cm), numbering: "1")
#set text(font: "New Computer Modern", size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.62em, first-line-indent: 1.2em, spacing: 0.62em)
#set heading(numbering: "1.1")
#show heading: set block(above: 1.3em, below: 0.7em)
#show heading.where(level: 1): set text(size: 12pt)
#show heading.where(level: 2): set text(size: 10.5pt, style: "italic", weight: "regular")
#show figure.caption: set text(size: 9pt)
#show figure.where(kind: table): set figure.caption(position: top)
#set table(stroke: (x, y) => (top: if y <= 1 { 0.6pt } else { 0pt }, bottom: 0.6pt), inset: (x: 5pt, y: 4pt))
#show table: set text(size: 9pt)
#set table(align: left)
#show table: set par(justify: false)

#align(center)[
  #text(size: 16pt, weight: "bold")[Raft under Physical Communication Models:\ What Relativity Changes, and What It Does Not]
  #v(0.6em)
  #text(size: 11pt)[Tomasz Kazulak] \
  #text(size: 9.5pt)[Independent study]
  #v(0.3em)
  #text(size: 9pt, fill: gray.darken(30%))[Structured literature survey · #datetime.today().display()]
]

#v(0.8em)
#block(inset: (x: 1.8em))[
  #set par(first-line-indent: 0em)
  #text(weight: "bold")[Abstract.]
  Consensus protocols such as Raft are specified against abstract communication
  models, while physical systems add constraints those models do not name: a
  finite signal speed, clocks that measure proper time, and no
  observer-independent simultaneity. We survey 34 studies, identified by
  targeted searches and backward and forward citation chasing and checked
  against their full texts, to establish what is known about Raft under
  non-ideal and physically grounded communication models. Three findings
  emerge. First, Raft's safety depends on no timing assumption and has recently
  been proved to survive relativistic causality. Second, the large literature on
  Raft under loss, partitions and variable delay concerns liveness and
  performance at the protocol level, and relativity adds nothing to it beyond a
  lower bound and a time dependence on delay. Third, the one Raft mechanism
  whose safety depends on clocks, the leader lease, has been analysed only
  against a common reference time: a bound on relative clock drift, a bounded
  uncertainty around true time, or timestamps whose relation to real time is
  delegated to another layer. None of these is stated frame-invariantly, and no
  study examines leases, or clock-based coordination generally, in relativistic
  spacetime. We identify this as the open problem and state candidate questions
  for an analytical follow-up.
]

= Introduction

Distributed-systems courses present consensus against an idealised network in
which messages are delayed arbitrarily but eventually delivered, and processes
share no clock @fischer1985 @dwork1988. A physicist reading these models
naturally asks whether they survive contact with the physical world. Signals
propagate no faster than light. Clocks on moving or gravitationally separated
nodes accumulate different proper times @ashby2003 @messerschmitt2023. And
relativity denies a global notion of "now", on which specifications such as
linearizability @herlihy1990 appear to depend, since they order operations by
real-time precedence @aeini2026. Lamport's logical clocks were themselves
motivated by special relativity @lamport1978, yet whether a concrete, widely
deployed protocol stays correct under physical constraints has only recently
been proved, for Raft @aeini2026, building on relativistic correctness
conditions of Gilbert and Golab @gilbert2014 and Jayanti @jayanti2025.

We take Raft @ongaro2014a as the object of study. It is widely deployed and
precisely specified, and it separates cleanly into a timing-independent safety
core and timing-dependent mechanisms. The survey's aim is to fix the boundaries
of current knowledge before any new analysis is attempted: what has been
established, what follows directly from established models, and what is open.

The contributions are
(i) a map of the communication models under which Raft and equivalent protocols have been analysed;
(ii) a classification of Raft's timing-dependent mechanisms by whether they affect safety or only liveness;
(iii) a synthesis of the small literature on distributed computing in relativistic spacetime; and
(iv) the identification of clock-based coordination under relativistic time as the open problem.

= Scope and research questions

The object is Raft and leader-based crash-fault-tolerant state-machine
replication whose results transfer to Raft. We consider communication models
ordered by the constraints they impose:
- synchronous;
- partially synchronous @dwork1988;
- asynchronous @fischer1985;
- asynchronous with loss, omission and partial partitions;
- delay- and disruption-tolerant networks @burleigh2003;
- relativistic spacetime, in which delivery respects the light-cone structure and each process measures its own proper time.

Out of scope are time-transfer engineering without a computational model,
quantum communication, and blockchain systems that use Raft as a black box.

/ RQ1: Under which communication models have Raft and equivalent protocols
  been analysed, for which properties, and with which methods?
/ RQ2: Which Raft mechanisms depend on timing or clock assumptions, for safety
  or only for liveness, and how are those assumptions stated?
/ RQ3: Which models of distributed computation in relativistic spacetime exist,
  and what correctness results do they establish?
/ RQ4: To what extent have clock-dependent mechanisms been analysed under
  relativistic or otherwise physically grounded models of time?

= Method

This is a structured survey rather than a full systematic review. It follows
the reporting logic of PRISMA 2020 @page2021 without claiming its complete
procedure, and it uses snowballing as described by Wohlin @wohlin2014.

*Identification.* Sixteen targeted web-search queries produced 149 records. A
first pass removed non-scholarly pages and duplicates, screened 73 records by
title and abstract, and retained 34. Backward citation chasing from these and
from the Raft literature added 19 records. These two counts come from the
search log of that first pass; the records it excluded were not re-screened.

*Forward snowballing.* Eight seeds were chosen as the studies most central to
the question that also have few enough citations to screen completely. Five
come from the relativistic and timekeeping strand @gilbert2014 @jayanti2025
@aeini2026 @messerschmitt2017 @matherat2003, and three concern Raft under
network faults and leases @jensen2021 @ng2023 @davis2025. Litmaps returned 56
citing records. Merging preprint and published versions and repeated entries
leaves 39 distinct works, of which 5 had already been identified. A ninth
intended seed, Mattern @mattern1992, is not indexed by Litmaps.

*Screening and eligibility.* Each record was first tagged as background
(foundational or method references cited for context, such as FLP, DLS,
linearizability, PRISMA and the lease and failure-detector classics) or as a
study; only studies were screened. A study was included if its subject is Raft
or leader-based crash-fault replication whose results transfer to Raft, a model
of distributed computation in relativistic spacetime, or quantified relativistic
or physical timekeeping in distributed systems; if an explicit communication,
timing or clock model is central to it; if it makes a technical contribution;
and if it is in English. Exclusion reasons were Raft as a black-box orderer,
Byzantine-only protocols, physics without a distributed-system model,
non-scholarly or insufficient detail, duplicates, and unavailable full text.
Title and abstract screening covered 75 distinct studies. Full texts were
retrieved from open-access sources for 35 of the 45 retained; the other 10 sit
behind publisher access controls and were excluded. Full-text eligibility
removed one more, leaving 34 studies, each summarised on an extraction card
(`review/cards.md`) and listed with every decision in `review/studies.csv`.
@tab:flow summarises the flow.

#figure(
  table(columns: (1fr, auto), align: (left, right),
    table.header[Stage][Records],
    [Targeted searches (first pass): retained], [34],
    [Backward citation chasing (first pass)], [19],
    [#h(1em) tagged background, not screened], [12],
    [Forward snowballing: citing records (8 seeds)], [56],
    [#h(1em) duplicates and versions merged], [17],
    [#h(1em) already identified], [5],
    [Studies screened on title and abstract], [75],
    [#h(1em) excluded], [30],
    [Full texts sought], [45],
    [#h(1em) not retrievable], [10],
    [Full texts assessed], [35],
    [#h(1em) excluded], [1],
    [*Studies included*], [*34*],
  ),
  caption: [Study selection. Counts for the first search pass are taken from its log; all later counts are from `review/studies.csv`.],
) <tab:flow>

= Use of AI assistance <sec:ai>

This survey was conducted with an AI assistant, Claude (Anthropic), in two
modes: through a chat interface connected to web search, the author's Zotero
library and arXiv, and as Claude Code working directly in the project
repository. We report the division of work because it bears directly on how far
the findings can be trusted.

*Performed by the assistant in chat:*
- proposing the research questions, search strings and eligibility criteria;
- running the targeted searches and the first screening pass;
- resolving bibliographic metadata and adding records to Zotero;
- drafting the text of this article;
- the preliminary lease argument in @sec:discussion and a numerical check of it.

*Performed by Claude Code:*
- tagging records as background or study, merging preprint and published versions, and attributing forward-snowballing records to their seeds using citation data from OpenAlex and Semantic Scholar;
- title and abstract screening of all studies against the stated criteria, with abstracts fetched by DOI or arXiv identifier where Zotero lacked them;
- retrieving open-access full texts and assessing full-text eligibility;
- extracting data from the full texts into one card per included study, with page references;
- checking every sentence of this article that attributes a result to a cited work against the cards, and correcting or removing the sentences that the full texts did not support.

*Performed by the author:*
- posing the motivating question and deciding the scope;
- choosing to reduce a full systematic review to a structured survey;
- confirming the snowballing seeds and running the forward chase in Litmaps, a citation index rather than a generative tool;
- approving the screening and the full-text eligibility decisions at two checkpoints, and taking responsibility for the result.

*Verification status.* Claims about included studies were checked against their
full texts; where only a preprint was openly available, the preprint was used.
Three studies central to the question, Gilbert and Golab @gilbert2014, Jayanti
@jayanti2025 and the Omni-Paxos paper @ng2023, could not be retrieved, and
statements about the first two rest on the account given by Aeini and Golab
@aeini2026. Background references were not checked against full texts.

The principal risks are misattributed or overstated claims, screening errors
that a second human reviewer would catch, and a uniform framing inherited from
a single drafting voice. Claude Code applied the eligibility criteria, and the
author reviewed its decisions rather than screening independently.

= Results

== RQ1: Communication models and methods

@tab:models maps the corpus. The division of labour is sharp. Protocol safety
is analysed by proof in the asynchronous model: Raft's TLA+ specification lets
the network reorder, drop and duplicate messages, and State Machine Safety is
proved against it by hand @ongaro2014. A Raft-derived protocol has been model
checked, with implementation traces validated against the specification, under
the same kind of network abstraction @howard2025. Almost everything else,
from lossy links to wireless and space deployments, is analysed for liveness,
latency or availability, by simulation, analytical modelling or testbeds. The
exceptions concern implementations rather than the protocol: real systems
violate safety under network partitions, for instance by letting an isolated
leader serve stale reads @alquraan2018, and model checking has found safety bugs
where an implementation diverged from Raft @howard2025.

#figure(
  table(columns: (auto, 1fr, auto),
    table.header[Model][What is analysed][Studies],
    [Asynchronous; loss, duplication, reordering], [Safety of the time-free core: TLA+ specification with hand proof; model checking and trace validation of a Raft variant; safety checks on simulation traces], [@ongaro2014 @ongaro2014a @howard2025 @howard2015],
    [Partially synchronous], [Liveness of leader election under the timing requirement that broadcast time be much less than the election timeout; election latency on LAN and simulated WAN], [@ongaro2014 @ongaro2014a @howard2015 @howard2014],
    [Partial and asymmetric connectivity], [Repeated elections and livelock under partial partitions; effect of PreVote, CheckQuorum and adaptive timeouts; real-world partition failures], [@jensen2021 @liang2024 @howard2014 @howard2025 @alquraan2018],
    [Unreliable channels], [Which channel failures consensus can tolerate; tight connectivity bounds], [@naser-pastoriza2023 @naser-pastoriza2025],
    [Probabilistic loss and delay], [Split probability, response time, availability and reliability as functions of loss rate, failure rates and timeouts], [@huang2018 @li2023 @li2026 @sakic2019],
    [Variable wide-area delay], [Adaptive or learned election timeouts; leader placement; randomised protocols whose liveness does not rest on timeouts], [@shiozaki2025 @wang2025 @wang2026 @tennage2023 @tennage2025],
    [Wireless, edge, space], [Raft variants and evaluations over vehicular, millimetre-wave, edge and satellite links; quorum design over light-time Earth–Moon–Mars delays], [@hu2026 @luo2023 @jeffery2023 @li2026a @mason2026],
    [Relativistic spacetime], [Relativistic linearizability of Raft under physical causality], [@aeini2026],
  ),
  caption: [Communication models under which Raft and equivalent protocols have been analysed.],
) <tab:models>

== RQ2: Timing-dependent mechanisms

Raft uses time in four places (@tab:timing). Election timeouts, heartbeats, and
the PreVote and CheckQuorum extensions affect only availability. Raft requires
that "safety must not depend on timing" @ongaro2014 and ensures at most one
leader per term @ongaro2014a; a badly tuned timeout causes needless or failed
elections @ongaro2014. How PreVote and CheckQuorum behave under partial
connectivity depends on the shape of the partition. PreVote stopped the repeated
elections in one emulated partial partition @jensen2021 but does not prevent
every disruptive-server case @ongaro2014. CheckQuorum can leave a well-connected
node's term lagging, so that recovery takes many election rounds
@liang2024. A leader that cannot receive messages can keep followers
from timing out @howard2025.

The exception is the leader lease used to serve linearizable reads without a
quorum round-trip. The Raft thesis extends the lease to the start of a
heartbeat round plus the election timeout divided by a clock drift bound, and
states the assumption as a bound on relative drift: over a given time period,
no server's clock advances more than this bound times any other. If it is
violated the system "could return arbitrarily stale information" @ongaro2014.

Recent lease designs state the clock assumption differently. LeaseGuard
assumes clocks with bounded uncertainty, each returning an interval guaranteed
to contain the true time, and loses linearizability if those bounds are wrong
@davis2025. T-Lease models synchronised clocks with a maximum drift rate
against a global time and treats an attacker who changes clock value or
frequency as the threat @trach2021. CockroachDB's Leader Leases rely only on
monotonic local clocks, carry hybrid-logical-clock timestamps on every message,
and prove that leases are disjoint over timestamps "on which both [nodes]
agree, although in real time the two nodes reach that timestamp at different
times". The link from those timestamps to real-time consistency is delegated
to a transaction layer that assumes loosely synchronised clocks @kettaneh2026.
ReadIndex, the quorum-based alternative, confirms leadership with one round of
heartbeats to a majority and uses no clock @ongaro2014.

#figure(
  table(columns: (auto, auto, 1fr),
    table.header[Mechanism][Affects][Timing assumption as stated],
    [Election timeout, heartbeat], [Liveness], [broadcastTime ≪ electionTimeout ≪ MTBF @ongaro2014],
    [PreVote, CheckQuorum], [Liveness], [As above; outcome under partial connectivity depends on partition shape],
    [Leader lease (lease reads)], [*Safety*], [Bounded relative clock drift @ongaro2014; bounded uncertainty around true time @davis2025; maximum drift rate @trach2021; disjointness over hybrid-logical-clock timestamps, real time delegated @kettaneh2026],
    [ReadIndex reads], [Neither], [None (one round of heartbeats to a majority)],
  ),
  caption: [Where Raft depends on time.],
) <tab:timing>

== RQ3: Distributed computing in relativistic spacetime

The strand is small, continuous and recent. Mattern observed that vector time
in distributed systems has the structure of Minkowski causality: for two
processes, vector-time order and light-cone order are basically identical, and
causality-preserving deformations of time diagrams correspond to Lorentz
transformations @mattern1992. Matherat and Jaekel argued that synchronous
circuits rely on the simultaneity classes of Newtonian space-time and
asynchronous circuits on the causal structure of relativistic space-time
@matherat2003. They later generalised the trace formalism for delay-insensitive
circuits to relativistic causality @matherat2011. Gilbert and Golab defined
relativistic variants of linearizability: an execution may be linearizable in
some frame of reference (R1), in every frame (R2), or with a single
linearization valid in all frames (R3) @gilbert2014 @aeini2026.

Jayanti's central theorem relates classical, relativistic and purely
computational executions; as characterised by Aeini and Golab, it establishes
R2-linearizability for asynchronous algorithms such as Raft @jayanti2025
@aeini2026. Aeini and Golab proved the strongest condition, R3, for any
execution of Raft, taking the final leader's log order as the single
linearization @aeini2026. Their model treats every operation as a log command,
so read optimisations are outside it. Forward chasing of all seeds surfaced no
further work in this strand.

A separate engineering literature quantifies relativistic timekeeping. In GPS,
the net rate offset of a satellite clock is about $4.46 times 10^(-10)$, and
clocks are synchronised by convention in an Earth-centred inertial frame
@ashby2003. For relativistic spacecraft, the query–response latency seen on one
node's clock follows from the trajectories @messerschmitt2023. Clock drift
between two nodes raises the average age of information, in closed form
@salimnejad2024.
None of it contains a model of distributed coordination.

== RQ4: Clock-based coordination under physical time

No study in the corpus analyses a clock-dependent consensus mechanism under a
relativistic model of time. The relativistic results cover asynchronous
algorithms, whose correctness makes no reference to clocks. Aeini and Golab
explicitly name algorithms that use physical clocks for coordination as future
work @aeini2026. The lease studies, conversely, reason against a common
reference time: relative drift @ongaro2014, uncertainty around true time
@davis2025, or a drift rate against a global clock @trach2021. The closest
contact is CockroachDB's design, which proves lease disjointness over timestamps
that nodes agree on while reaching them at different real times, but leaves the
step from timestamps to real-time consistency to a layer that assumes loosely
synchronised clocks @kettaneh2026. The timekeeping studies have no protocol
model. The two literatures do not meet.

= Discussion <sec:discussion>

We separate what is established, what follows directly from established models,
and what is open.

*Established.*
- Raft's safety is independent of timing @ongaro2014 and holds under relativistic causality @aeini2026.
- Its liveness requires the timing requirement broadcastTime ≪ electionTimeout ≪ MTBF @ongaro2014, and fails in specific ways under partial and asymmetric connectivity @jensen2021 @liang2024 @howard2025.
- Its only timing-dependent safety mechanism is the leader lease @ongaro2014.

*Directly derivable.* Three consequences follow from the models above without
new results.
- A network that delivers messages only into the sender's future light cone produces a subset of asynchronous executions, so every asynchronous safety argument transfers. This matches the execution model used by Aeini and Golab, in which physical causality refines Lamport's happens-before relation @aeini2026.
- Physics bounds message delay from below, by distance over $c$, and makes it time-varying. This instantiates partial synchrony rather than replacing it, so for liveness relativity is "just delay".
- @tab:magnitudes compares the sizes involved. The largest motion-induced effect is first order in $beta = v\/c$ and is kinematic: a changing propagation delay. Genuinely relativistic rate effects are second order, or of order $Delta Phi \/ c^2$ for gravity, and lie orders of magnitude below the tolerance of commodity oscillators.

#figure(
  table(columns: (1fr, auto, 1fr),
    table.header[Effect][Order][Typical size],
    [Changing propagation delay (first-order Doppler)], [$beta$], [$5 times 10^(-5)$ between LEO satellites; $10^(-4)$ at Earth's orbital speed],
    [Time dilation], [$beta^2 \/ 2$], [$approx 3 times 10^(-10)$ in low Earth orbit],
    [Net rate offset, GPS orbit vs. geoid (gravitational blueshift less time dilation)], [$Delta Phi \/ c^2$, $beta^2 \/ 2$], [$approx 4.46 times 10^(-10)$ @ashby2003],
    [Commodity quartz oscillator tolerance], [—], [$10^(-5)$ to $10^(-4)$],
  ),
  caption: [Orders of magnitude of rate effects relevant to timeouts and leases.],
) <tab:magnitudes>

*Open.* What does not reduce to delay is the relativity of simultaneity, and
it bites exactly where a protocol converts elapsed time on one clock into a
claim about another node. "Bounded drift between two clocks" presupposes a
simultaneity convention for comparing distant clocks, as do "uncertainty around
true time" and "drift against a global clock". None of these is a
frame-invariant assumption. CockroachDB's timestamp-domain disjointness comes
closest to avoiding the convention, but it still needs synchronised clocks to
turn disjoint timestamps into fresh reads @kettaneh2026. The lease safety
argument therefore has no frame-invariant statement in the literature.

A preliminary observation, to be verified rather than relied upon, suggests
what such a statement might look like. The causal chain that could make a lease
read stale passes through the follower's timer. By the reverse triangle
inequality of Minkowski spacetime, an inertial leader's proper time along that
chain is at least the follower's timeout. If so, first-order Doppler effects
cancel, and only a leader whose worldline is not a geodesic, whether
accelerating or held static in a gravitational field, can lose lease time: a
twin-paradox effect.

= Threats to validity

The survey had a single human reviewer, and screening, extraction and drafting
were AI-assisted (@sec:ai). Identification relied on targeted web search rather
than on Scopus or Web of Science, and the queries were partly seeded with known
items, which biases toward known work; records excluded by the first search
pass were not re-screened. Ten studies were excluded only because their full
texts were not openly retrievable, among them two foundational relativistic
studies @gilbert2014 @jayanti2025, a machine-checked proof of Raft's safety
@woos2016 and Omni-Paxos @ng2023. Where only a preprint was available, it was
used in place of the published version. Forward snowballing depends on Litmaps'
index: one intended seed was not indexed, and the most recent seed has no
citations yet. The relativistic strand is small enough that we believe the
forward chase covers it. The Raft-under-faults strand is large, and it is
represented rather than exhausted.

= Conclusion and next steps

Physics changes little about Raft. Its safety core survives relativistic
causality, and its liveness sees physics only as delay. The single point of
contact is the leader lease, the one mechanism that turns local elapsed time
into a claim about other nodes. Its safety assumption has never been stated in
frame-invariant form; the nearest approach, disjointness over agreed
timestamps, still relies on synchronised clocks to make reads fresh. We take
the following candidate questions to the analytical phase:

+ What is the frame-invariant condition under which a Raft leader lease is safe?
+ In which physically realistic configurations, such as satellites, ground–orbit links and interplanetary distances, does that condition differ measurably from the classical bounded-drift rule?
+ Does a lease-based read satisfy the strongest relativistic linearizability condition that Raft satisfies without leases @aeini2026?

#bibliography("refs.bib", style: "ieee", title: "References")
