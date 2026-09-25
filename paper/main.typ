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
  observer-independent simultaneity. We survey 60 studies, identified by
  targeted searches and forward citation chasing, to establish what is known
  about Raft under non-ideal and physically grounded communication models.
  Three findings emerge. First, Raft's safety depends on no timing assumption and
  has recently been shown to survive relativistic causality. Second, the large
  literature on Raft under loss, partitions and variable delay concerns
  liveness and performance, and relativity adds nothing to it beyond a lower
  bound and a time dependence on delay. Third, the one Raft mechanism whose
  safety depends on clocks, the leader lease, has been analysed only under
  bounded clock drift, an assumption that is not frame-invariant. No study
  examines leases, or clock-based coordination generally, in relativistic
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
linearizability @herlihy1990 appear to depend. Lamport's logical clocks were
themselves motivated by special relativity @lamport1978, yet whether a concrete,
widely deployed protocol stays correct under physical constraints has only
recently been studied formally @gilbert2014 @jayanti2025 @aeini2026.

We take Raft @ongaro2014 as the object of study. It is widely deployed and
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

*Identification.* Sixteen targeted web-search queries produced 149 records. We
removed non-scholarly pages and duplicates, screened 73 records by title and
abstract, and included 34. Backward citation chasing from these and from the
Raft literature added 19 foundational studies.

*Forward snowballing.* Eight seeds were chosen as the studies most central to
the question that also have few enough citations to screen completely. Five
come from the relativistic and timekeeping strand @gilbert2014 @jayanti2025
@aeini2026 @messerschmitt2017 @matherat2003, and three concern Raft under
network faults and leases @jensen2021 @ng2023 @davis2025. Litmaps returned 56
citing records. They collapse to 39 distinct works once preprint and published
versions are merged. Of these, 5 were already included, 7 were newly included,
and 27 were excluded as off-topic: optics, AI for systems research, cluster
operations, and essays on computation and physics. A ninth intended seed,
Mattern @mattern1992, is not indexed by Litmaps.

*Result.* The final corpus has 60 studies. Title and abstract screening was
performed by an AI assistant and accepted by the author (@sec:ai).
@tab:flow summarises the flow.

#figure(
  table(columns: (1fr, auto), align: (left, right),
    table.header[Stage][Records],
    [Targeted searches: records identified], [149],
    [After removing non-scholarly records and duplicates], [73],
    [Included from searches], [34],
    [Added by backward citation chasing], [19],
    [Forward snowballing: citing records (8 seeds)], [56],
    [#h(1em) distinct works after merging versions], [39],
    [#h(1em) newly included], [7],
    [*Final corpus*], [*60*],
  ),
  caption: [Study selection.],
) <tab:flow>

= Use of AI assistance <sec:ai>

This survey was conducted with an AI assistant, Claude (Anthropic), used
through a chat interface connected to web search, the author's Zotero library
and arXiv. Claude Code was used to set up the software environment. We
report the division of work because it bears directly on how far the findings
can be trusted.

*Performed by the assistant:*
- proposing the research questions, search strings and eligibility criteria;
- running the targeted searches;
- screening titles and abstracts, including the forward-snowballing results;
- resolving bibliographic metadata and adding records to Zotero;
- drafting the text of this article;
- the preliminary lease argument in @sec:discussion and a numerical check of it.

*Performed by the author:*
- posing the motivating question and deciding the scope;
- choosing to reduce a full systematic review to a structured survey;
- confirming the snowballing seeds and running the forward chase in Litmaps, a citation index rather than a generative tool;
- approving each stage, and taking responsibility for the result.

*Verification status.* Bibliographic records were resolved from DOIs or arXiv
identifiers wherever these existed; records without them were flagged.
Statements about individual studies were checked against titles, abstracts and
search excerpts, not against full texts. A few characterisations, of results
that are standard in the field, rest on the assistant's background knowledge.
These are the timing requirements and read mechanisms of Raft, and the network
semantics of its machine-checked proof. Full-text verification of every claim
attributed to a cited study is pending.

The principal risks are misattributed or overstated claims, screening errors
that a second human reviewer would catch, and a uniform framing inherited from
a single drafting voice.

= Results

== RQ1: Communication models and methods

@tab:models maps the corpus. The division of labour is sharp. Safety is
analysed by proof under the asynchronous model, and it has been machine-checked
for Raft under a network that drops, duplicates and reorders messages
@woos2016. Everything else, from lossy links to wireless and space deployments,
is analysed for liveness, latency or availability, by simulation, analytical
modelling or testbeds.

#figure(
  table(columns: (auto, 1fr, auto),
    table.header[Model][What is analysed][Studies],
    [Asynchronous], [Safety of the time-free core; machine-checked proofs], [@ongaro2014 @woos2016],
    [Partially synchronous], [Liveness of leader election; timing requirement that broadcast time be much less than the election timeout], [@dwork1988 @ongaro2014thesis],
    [Omission, partial connectivity], [Livelock and leaderlessness under partial partitions; PreVote and CheckQuorum counterexamples; real-world partition failures], [@jensen2021 @howard2020 @ng2023 @alquraan2018],
    [Unreliable channels], [Which channel failures consensus can tolerate; tight bounds via generalised quorum systems], [@naserpastoriza2023 @naserpastoriza2025],
    [Probabilistic loss and delay], [Split probability, commit latency and reliability as functions of loss rate and timeouts], [@huang2018 @li2023 @li2026dcn @sakic2019 @howard2015],
    [Variable wide-area delay], [Adaptive or learned election timeouts; randomised protocols whose liveness does not rest on timeouts], [@shiozaki2025 @wang2025 @tennage2023 @tennage2025],
    [Wireless, edge, space], [Raft variants and evaluations for vehicular, edge and satellite links; DTN architecture], [@hu2026 @jeffery2023 @li2026a @burleigh2003 @cerf2007],
    [Relativistic spacetime], [Correctness conditions and safety proofs under causal (light-cone) delivery], [@gilbert2014 @jayanti2025 @aeini2026],
  ),
  caption: [Communication models under which Raft and equivalent protocols have been analysed.],
) <tab:models>

== RQ2: Timing-dependent mechanisms

Raft uses time in four places (@tab:timing). Election timeouts, heartbeats, and
the PreVote and CheckQuorum extensions affect only availability: a badly tuned
timeout causes needless or failed elections but never two leaders in one term
@ongaro2014 @ongaro2014thesis. The exception is the leader lease used to serve
linearizable reads without a quorum round-trip. Its safety requires that the
leader's lease expire, on the leader's clock, before any follower's election
timeout could have let a new leader emerge. That in turn needs a bound on how
far the two clocks' rates can diverge @ongaro2014thesis.

The lease literature states this assumption as a bounded drift rate relative to
real time. This holds for the original lease mechanism @gray1989, for the
general treatment of clocks in distributed protocols @liskov1993, and for recent
Raft-specific designs, including a TLA+-verified Raft lease @davis2025 and a
production design for many consensus groups @kettaneh2026. Adversarial
manipulation of clock rates is treated as a threat to lease safety @trach2021.
ReadIndex, the quorum-based alternative, uses no clock and is safe
asynchronously @ongaro2014thesis.

#figure(
  table(columns: (auto, auto, 1fr),
    table.header[Mechanism][Affects][Timing assumption],
    [Election timeout, heartbeat], [Liveness], [Partial synchrony; timeout well above round-trip time],
    [PreVote, CheckQuorum], [Liveness], [As above; known liveness gaps under partial connectivity],
    [Leader lease (lease reads)], [*Safety*], [Bounded clock-rate divergence between leader and followers],
    [ReadIndex reads], [Neither], [None (one quorum round-trip)],
  ),
  caption: [Where Raft depends on time.],
) <tab:timing>

== RQ3: Distributed computing in relativistic spacetime

The strand is small, continuous and recent. Mattern observed that vector time
in distributed systems has the structure of Minkowski causality @mattern1992.
Matherat and Jaekel showed that synchronous and asynchronous circuits mirror
Newtonian and relativistic causal structures @matherat2003 @matherat2011.
Gilbert and Golab were the first to ask what linearizability means when
operations are only partially ordered by causality, and proposed relativistic
variants of it @gilbert2014.

Jayanti gave a single execution model covering classical and relativistic
systems, and showed that correctness established for asynchronous algorithms
carries over @jayanti2025. Aeini, Golab, Olivetti and Ruppert proved the
strongest of Gilbert and Golab's conditions for Raft @aeini2026, and Jayanti
and Natarajan extended the causal model to quantum systems @jayanti2026.
Forward chasing of all seeds surfaced no further work in this strand.

A separate engineering literature quantifies relativistic timekeeping: its
magnitude in navigation and communications @ashby2003 @messerschmitt2017
@messerschmitt2023, and its effect on information freshness
@salimnejad2025 @kovacevic2024. None of it contains a model of distributed
coordination.

== RQ4: Clock-based coordination under physical time

No study in the corpus analyses a clock-dependent consensus mechanism under a
relativistic model of time. The relativistic results cover asynchronous
algorithms, whose correctness makes no reference to clocks. Aeini et al.
explicitly name algorithms that use physical clocks for coordination as future
work @aeini2026. The lease studies, conversely, assume bounded drift relative to
a common real time @davis2025 @kettaneh2026, and the timekeeping studies have no
protocol model. The two literatures do not meet.

= Discussion <sec:discussion>

We separate what is established, what follows directly from established models,
and what is open.

*Established.*
- Raft's safety is independent of timing and holds under relativistic causality @woos2016 @aeini2026.
- Its liveness requires partial synchrony @dwork1988 and fails in specific, well-characterised ways under partial connectivity @jensen2021 @ng2023.
- Its only timing-dependent safety mechanism is the leader lease @ongaro2014thesis.

*Directly derivable.* Three consequences follow from the models above without
new results.
- A network that delivers messages only into the sender's future light cone produces a subset of asynchronous executions, so every asynchronous safety argument transfers. This is the intuition behind @jayanti2025.
- Physics bounds message delay from below, by distance over $c$, and makes it time-varying. This instantiates partial synchrony rather than replacing it, so for liveness relativity is "just delay".
- @tab:magnitudes compares the sizes involved. The largest motion-induced effect is first order in $beta = v\/c$ and is kinematic: a changing propagation delay. Genuinely relativistic rate effects are second order, or of order $Delta Phi \/ c^2$ for gravity, and lie orders of magnitude below the tolerance of commodity oscillators.

#figure(
  table(columns: (1fr, auto, 1fr),
    table.header[Effect][Order][Typical size],
    [Changing propagation delay (first-order Doppler)], [$beta$], [$5 times 10^(-5)$ between LEO satellites; $10^(-4)$ at Earth's orbital speed],
    [Time dilation], [$beta^2 \/ 2$], [$approx 3 times 10^(-10)$ in low Earth orbit],
    [Gravitational rate difference], [$Delta Phi \/ c^2$], [$approx 4.5 times 10^(-10)$, GPS orbit vs. ground @ashby2003],
    [Commodity quartz oscillator tolerance], [—], [$10^(-5)$ to $10^(-4)$],
  ),
  caption: [Orders of magnitude of rate effects relevant to timeouts and leases.],
) <tab:magnitudes>

*Open.* What does not reduce to delay is the relativity of simultaneity, and
it bites exactly where a protocol converts elapsed time on one clock into a
claim about another node. "Bounded drift between two clocks" presupposes a
simultaneity convention for comparing distant clocks. It is therefore not a
frame-invariant assumption, and the lease safety argument has no
frame-invariant statement in the literature.

A preliminary observation, to be verified rather than relied upon, suggests
what such a statement might look like. The causal chain that could make a lease
read stale passes through the follower's timer. By the reverse triangle
inequality of Minkowski spacetime, an inertial leader's proper time along that
chain is at least the follower's timeout. If so, first-order Doppler effects
cancel, and only a leader whose worldline is not a geodesic, whether
accelerating or held static in a gravitational field, can lose lease time: a
twin-paradox effect.

= Threats to validity

The survey had a single human reviewer, and screening and drafting were
AI-assisted (@sec:ai), with full-text verification still pending. Identification relied on targeted web search
rather than on Scopus or Web of Science, and the queries were partly seeded
with known items, which biases toward known work. Forward snowballing depends
on Litmaps' index: one intended seed was not indexed, and the most recent seed
has no citations yet. The relativistic strand is small enough that we believe
the forward chase covers it. The Raft-under-faults strand is large, and it is
represented rather than exhausted.

= Conclusion and next steps

Physics changes little about Raft. Its safety core survives relativistic
causality, and its liveness sees physics only as delay. The single point of
contact is the leader lease, the one mechanism that turns local elapsed time
into a claim about other nodes. Its safety assumption has never been stated in
frame-invariant form. We take the following candidate questions to the
analytical phase:

+ What is the frame-invariant condition under which a Raft leader lease is safe?
+ In which physically realistic configurations, such as satellites, ground–orbit links and interplanetary distances, does that condition differ measurably from the classical bounded-drift rule?
+ Does a lease-based read satisfy the strongest relativistic linearizability condition that Raft satisfies without leases @aeini2026?

#bibliography("refs.bib", style: "ieee", title: "References")
