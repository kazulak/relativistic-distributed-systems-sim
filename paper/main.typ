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
  observer-independent simultaneity. We survey 41 studies, identified by
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
nodes accumulate different proper times @ashby2003 @messerschmitt2017. And
relativity denies a global notion of "now", on which specifications such as
linearizability @herlihy1990 depend: their definition assumes a total temporal
order, "tantamount to assuming the existence of a global clock" @gilbert2014.
Lamport's logical clocks were themselves motivated by special relativity
@lamport1978, yet whether a concrete, widely deployed protocol stays correct
under physical constraints has only recently been proved, for Raft
@aeini2026, building on relativistic correctness conditions of Gilbert and
Golab @gilbert2014 and Jayanti @jayanti2025.

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

*Additional citation chasing.* Because the relativistic strand is small and
central, two further checks were run. Backward: the reference lists of Aeini and
Golab @aeini2026, Gilbert and Golab @gilbert2014 and Jayanti @jayanti2025
contributed 13 records not already identified. Forward: every work citing
Gilbert and Golab or Mattern was retrieved from OpenAlex and Semantic Scholar,
since Google Scholar cannot be queried by script, contributing 20 records not
already identified. Together these added two studies @lamport1986 @landers2026.

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
Title and abstract screening covered 103 distinct studies. Full texts were
obtained for 42 of the 47 retained, from open-access sources, the authors'
sites, or the author's institutional access; the other 5 were excluded as
unavailable. Full-text eligibility removed one more, leaving 41 studies, each
summarised on an extraction card (`review/cards.md`) and listed with every
decision in `review/studies.csv`. @tab:flow summarises the flow.

#figure(
  table(columns: (1fr, auto), align: (left, right),
    table.header[Stage][Records],
    [Targeted searches (first pass): retained], [34],
    [Backward citation chasing (first pass)], [19],
    [#h(1em) tagged background, not screened], [12],
    [Forward snowballing via Litmaps: citing records (8 seeds)], [56],
    [#h(1em) duplicates and versions merged], [17],
    [#h(1em) already identified], [5],
    [Additional backward chasing (3 reference lists)], [13],
    [#h(1em) tagged background, not screened], [2],
    [Additional forward chasing (2 seeds, OpenAlex and Semantic Scholar)], [20],
    [#h(1em) duplicates and versions merged], [3],
    [Studies screened on title and abstract], [103],
    [#h(1em) excluded], [56],
    [Full texts sought], [47],
    [#h(1em) not retrievable], [5],
    [Full texts assessed], [42],
    [#h(1em) excluded], [1],
    [*Studies included*], [*41*],
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
- retrieving full texts, from open-access sources and, with the author's permission, through the author's browser session, and assessing full-text eligibility;
- the additional backward and forward citation chasing described in the Method;
- checking the authors, title and year of every bibliography entry that has a DOI or arXiv identifier against Crossref or arXiv;
- extracting data from the full texts into one card per included study, with page references;
- checking every sentence of this article that attributes a result to a cited work against the cards, and correcting or removing the sentences that the full texts did not support.

*Performed by the author:*
- posing the motivating question and deciding the scope;
- choosing to reduce a full systematic review to a structured survey;
- confirming the snowballing seeds and running the forward chase in Litmaps, a citation index rather than a generative tool;
- supplying full texts that could not be retrieved automatically;
- approving the screening and the full-text eligibility decisions at two checkpoints, and taking responsibility for the result.

*Verification status.* Claims about included studies were checked against their
full texts; where only a preprint was openly available, the preprint was used.
Background references were not checked against full texts. Every bibliography
entry with a DOI or arXiv identifier matches the registry's authors; entries
without one were checked against the title pages of the retrieved texts.
Metadata that the chat assistant took from search snippets and that no
identifier confirms should be treated as unverified. An earlier reference file
listed four authors for Aeini and Golab @aeini2026, which has two.

The principal risks are misattributed or overstated claims, screening errors
that a second human reviewer would catch, and a uniform framing inherited from
a single drafting voice. Claude Code applied the eligibility criteria, and the
author reviewed its decisions rather than screening independently; approving
decisions made by someone else invites automation bias. An independent blind
check by the author, re-screening 20 randomly drawn records
(`review/blind-check.csv`, seed 20260926) without seeing the recorded
decisions, is prepared and its agreement rate is to be reported here.

= Results

== RQ1: Communication models and methods

@tab:models maps the corpus. The division of labour is sharp. Protocol safety
is analysed by proof in the asynchronous model: Raft's TLA+ specification lets
the network reorder, drop and duplicate messages, and State Machine Safety is
proved against it by hand @ongaro2014. A machine-checked proof in Coq
establishes the same property, and end-to-end linearizable replication, for an
implementation under a network semantics with drops, duplication and
reordering; it covers safety only @woos2016. A Raft-derived protocol has been model
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
    [Asynchronous; loss, duplication, reordering], [Safety of the time-free core: TLA+ specification with hand proof; machine-checked proof in Coq; model checking and trace validation of a Raft variant; safety checks on simulation traces], [@ongaro2014 @ongaro2014a @woos2016 @howard2025 @howard2015],
    [Partially synchronous], [Liveness of leader election under the timing requirement that broadcast time be much less than the election timeout; election latency on LAN and simulated WAN], [@ongaro2014 @ongaro2014a @howard2015 @howard2014],
    [Partial and asymmetric connectivity], [Repeated elections and livelock under partial partitions; effect of PreVote, CheckQuorum and adaptive timeouts; real-world partition failures], [@jensen2021 @ng2023 @liang2024 @howard2014 @howard2025 @alquraan2018],
    [Unreliable channels], [Which channel failures consensus can tolerate; tight connectivity bounds], [@naser-pastoriza2023 @naser-pastoriza2025],
    [Probabilistic loss and delay], [Split probability, response time, availability and reliability as functions of loss rate, failure rates and timeouts], [@huang2018 @li2023 @li2026 @sakic2019],
    [Variable wide-area delay], [Adaptive or learned election timeouts; leader placement; randomised protocols whose liveness does not rest on timeouts], [@shiozaki2025 @wang2025 @wang2026 @tennage2023 @tennage2025],
    [Wireless, edge, space], [Raft variants and evaluations over vehicular, millimetre-wave, edge and satellite links; quorum design over light-time Earth–Moon–Mars delays], [@hu2026 @luo2023 @jeffery2023 @li2026a @mason2026],
    [Relativistic spacetime], [Relativistic linearizability of Raft under physical causality; transfer of asynchronous correctness to relativistic executions], [@aeini2026 @jayanti2025],
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
every disruptive-server case @ongaro2014. With PreVote and CheckQuorum enabled,
Raft recovers from the quorum-loss and chained scenarios but stays unavailable
for the whole partition when the only quorum-connected server has an outdated
log, because a Raft leader must also hold the most up-to-date log @ng2023.
CheckQuorum can leave a well-connected
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

The strand is small, continuous and recent. Lamport's formalism for
interprocess communication already admitted executions whose events are points
of four-dimensional spacetime ordered by the happens-before relation of special
relativity, next to the more familiar global-time models @lamport1986. Mattern
observed that vector time in distributed systems has the structure of Minkowski
causality: for two
processes, vector-time order and light-cone order are basically identical, and
causality-preserving deformations of time diagrams correspond to Lorentz
transformations @mattern1992. Matherat and Jaekel argued that synchronous
circuits rely on the simultaneity classes of Newtonian space-time and
asynchronous circuits on the causal structure of relativistic space-time
@matherat2003. They later generalised the trace formalism for delay-insensitive
circuits to relativistic causality @matherat2011.

Gilbert and Golab defined four relativistic variants of linearizability that
need no global clock and form a hierarchy: R0, the direct generalisation to
partially ordered events; R1, linearizable in some frame of reference; R2, in
every frame; and R3, in every frame with a single common linearization. Only R2
is local, which is why they consider it the most natural definition. R3 is the
strongest condition, is easier to reason about, and is not local. They also
give sufficient conditions for deducing R2 and R3 from R1, and remark, without a
full proof, that Paxos state machine replication satisfies them and so yields
R3 @gilbert2014. Jayanti's central theorem relates classical, relativistic and
purely computational executions of asynchronous algorithms: an algorithm
satisfies a property classically if and only if it does in every observer's
frame, so every linearizable algorithm is relativistically linearizable. His
definition differs slightly from R2 by admitting only orderings that correspond
to actual reference frames, and his model has no clocks @jayanti2025. Aeini and
Golab proved R3 for any execution of Raft, taking the final leader's log order
as the single linearization @aeini2026. Their model treats every operation as a
log command, so read optimisations are outside it.

Forward chasing from all seeds and the additional chasing found one further
work. It frames consistency models as observers of a causal graph and argues
that linearizability needs a global serializer because a single order over
spacelike-separated operations is "a preferred frame" no observer's light cone
supplies. Its relativistic reading is explicitly interpretive; the model itself
uses Newtonian real time @landers2026.

A separate engineering literature quantifies relativistic timekeeping. It
gives closed-form models of relativistic clock rate and synchronisation for
system designers, and notes that some distributed computing needs time
intervals rather than ordering alone @messerschmitt2017. In GPS,
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
algorithms, whose correctness makes no reference to clocks; Jayanti's model has
no clocks at all @jayanti2025. Aeini and Golab explicitly name algorithms that
use physical clocks for coordination as future work @aeini2026. A general
condition for when ordering by physical clocks respects causality, namely that
timestamp order refines causality if and only if twice the clock-error bound
does not exceed the minimum cross-node latency, is stated against Newtonian
real time @landers2026. The lease studies, conversely, reason against a common
reference time: relative drift @ongaro2014, uncertainty around true time
@davis2025, or a drift rate against a global clock @trach2021. The closest
contact is CockroachDB's design, which proves lease disjointness over timestamps
that nodes agree on while reaching them at different real times, but leaves the
step from timestamps to real-time consistency to a layer that assumes loosely
synchronised clocks @kettaneh2026. The timekeeping studies have no protocol
model. The two literatures do not meet.

= Discussion <sec:discussion>

We separate what the surveyed studies establish from our own reasoning. Only
the first list below reports findings of the literature; everything after it
is the authors' reasoning or conjecture, is not a result of this survey, and is
marked as such.

*Established by the surveyed studies.*
- Raft's safety is independent of timing @ongaro2014, is machine-checked for an implementation @woos2016, and holds under relativistic causality @jayanti2025 @aeini2026.
- Its liveness requires the timing requirement broadcastTime ≪ electionTimeout ≪ MTBF @ongaro2014, and fails in specific ways under partial and asymmetric connectivity @jensen2021 @ng2023 @liang2024 @howard2025.
- Its only timing-dependent safety mechanism is the leader lease @ongaro2014.

*Our reasoning, not a finding of the survey.* Three consequences seem to follow
from the models above without new results.
- A network that delivers messages only into the sender's future light cone produces a subset of asynchronous executions, so every asynchronous safety argument transfers. Jayanti's equivalence theorem proves a general form of this for asynchronous algorithms @jayanti2025.
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

*Open (our interpretation of the gap).* What does not reduce to delay is the relativity of simultaneity, and
it bites exactly where a protocol converts elapsed time on one clock into a
claim about another node. "Bounded drift between two clocks" presupposes a
simultaneity convention for comparing distant clocks, as do "uncertainty around
true time" and "drift against a global clock". None of these is a
frame-invariant assumption. CockroachDB's timestamp-domain disjointness comes
closest to avoiding the convention, but it still needs synchronised clocks to
turn disjoint timestamps into fresh reads @kettaneh2026. The lease safety
argument therefore has no frame-invariant statement in the literature.

*Conjecture (ours, unverified; not a finding of this survey).* A preliminary
observation, to be verified rather than relied upon, suggests what such a
statement might look like. The causal chain that could make a lease
read stale passes through the follower's timer. By the reverse triangle
inequality of Minkowski spacetime, an inertial leader's proper time along that
chain is at least the follower's timeout. If so, first-order Doppler effects
cancel, and only a leader whose worldline is not a geodesic, whether
accelerating or held static in a gravitational field, can lose lease time: a
twin-paradox effect.

= Threats to validity

*The gap was a hypothesis before the search.* The lease question was proposed
by the chat assistant in its first answer, before any screening, and it shaped
the search terms, the eligibility criteria and the choice of snowballing seeds.
The survey was therefore aimed at the gap it reports, and a reader should weigh
the RQ4 conclusion accordingly. Independent support comes from Aeini and Golab,
who name clock-based algorithms as future work in their own words @aeini2026.

*Screening.* The survey had a single human reviewer, and screening, extraction
and drafting were AI-assisted (@sec:ai). The author approved decisions made by
the AI rather than making them, which invites automation bias; the blind
re-screening described in @sec:ai is the check on this.

*Identification.* Identification relied on targeted web search rather than on
Scopus or Web of Science, and the queries were partly seeded with known items,
which biases toward known work. Only counts survive from the 149 records of the
first search pass, not the records themselves, so that pass cannot be
reproduced and its exclusions were not re-screened. Forward snowballing
depends on Litmaps' index, which does not cover one intended seed; for that
seed and for Gilbert and Golab, citing works were taken from OpenAlex and
Semantic Scholar instead of Google Scholar, and those indexes may miss citations
from venues they cover poorly. The relativistic strand is small enough that we
believe the combined chase covers it. The Raft-under-faults strand is large,
and it is represented rather than exhausted.

*Retrieval.* Five studies were excluded only because their full texts could
not be obtained; none is central to the research questions. Where only a
preprint was available, it was used in place of the published version.

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
