// Raft under physical communication models: systematic review
// Build: typst compile paper/main.typ   |   live: typst watch paper/main.typ
// refs.bib is auto-exported by Better BibTeX from the Zotero collection "Raft"
// (citation key formula: auth.lower + year).

#let todo(body) = text(fill: rgb("#b00020"), [\[#body\]])

#set document(title: "Raft under Physical Communication Models", author: "Author")
#set page(paper: "a4", margin: (x: 2.4cm, y: 2.6cm), numbering: "1")
#set text(font: "New Computer Modern", size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.62em, first-line-indent: 1.2em, spacing: 0.62em)
#set heading(numbering: "1.1")
#show heading: set block(above: 1.3em, below: 0.7em)
#show heading.where(level: 1): set text(size: 12pt)
#show heading.where(level: 2): set text(size: 10.5pt, style: "italic", weight: "regular")
#show figure.caption: set text(size: 9pt)
#set enum(indent: 0.6em)

#align(center)[
  #text(size: 16pt, weight: "bold")[Raft under Physical Communication Models:\ A Systematic Review of What Relativity Changes]
  #v(0.6em)
  #text(size: 11pt)[Author Name] \
  #text(size: 9.5pt)[Affiliation · email]
  #v(0.3em)
  #text(size: 9pt, fill: gray.darken(30%))[Working draft · protocol stage · #datetime.today().display()]
]

#v(0.8em)
#block(inset: (x: 1.8em))[
  #set par(first-line-indent: 0em)
  #text(weight: "bold")[Abstract.]
  Consensus protocols such as Raft are specified against abstract communication
  models: asynchronous or partially synchronous message passing, possibly with
  loss and partitions. Physical systems add constraints those models do not name
  explicitly: a finite signal speed, clocks that measure proper time, and, in
  relativistic settings, no observer-independent simultaneity. This review asks
  which of these constraints are already accounted for by existing results,
  which reduce to known communication models, and which remain open. We follow
  PRISMA 2020 @page2021 and the software-engineering guidelines of Kitchenham
  and Charters @kitchenham2007, combining database search with backward and
  forward snowballing @wohlin2014. #todo[Results and conclusions after screening.]
]

= Introduction

Distributed-systems courses present consensus against an idealised network in
which messages are delayed arbitrarily but eventually delivered, and processes
share no clock @fischer1985 @dwork1988. A physicist reading these models
naturally asks whether they survive contact with the physical world. Signals
propagate no faster than light, clocks on moving or gravitationally separated
nodes accumulate different proper times, and relativity denies a global notion
of "now" on which specifications such as linearizability @herlihy1990 appear to
depend. Lamport's logical clocks were themselves motivated by special relativity
@lamport1978, yet the question of whether a concrete, widely deployed protocol
remains correct under physical constraints has only recently been studied
formally @gilbert2014 @jayanti2025 @aeini2026.

This review takes Raft as its object because it is widely deployed, precisely
specified, and separates cleanly into a timing-independent safety core and
timing-dependent mechanisms. The review's purpose is to establish the boundaries
of current knowledge before any new analysis is attempted: what is known, what
follows directly from known models, and what is genuinely open.

#todo[One paragraph stating the contributions once results exist.]

= Scope and boundaries

== Object of study
The object is Raft and leader-based crash-fault-tolerant state-machine
replication whose results transfer to Raft (Multi-Paxos, Viewstamped
Replication). Byzantine protocols are excluded except where they provide the
only analysis of a communication model.

== Communication models
We consider a hierarchy of models ordered by the constraints they impose:
synchronous; partially synchronous @dwork1988; asynchronous @fischer1985;
asynchronous with loss, omission and partial partitions; delay- and
disruption-tolerant networks; and relativistic spacetime, in which message
delivery is constrained by the causal (light-cone) structure and each process
measures its own proper time. Clock-based mechanisms (leases, bounded-drift
assumptions, failure detectors) are included wherever a model's timing
assumptions enter a correctness argument.

== Out of scope
Time-transfer engineering without a computational model, quantum communication,
blockchain papers that use Raft only as a black-box ordering service, and
performance tuning that does not state a communication model.

= Research questions

The review addresses four questions. The first two map the field; the third
isolates the physically grounded literature; the fourth identifies the gap from
which the research questions of the subsequent analytical phase will be drawn.

/ RQ1 (mapping): Under which communication models have Raft and equivalent
  protocols been analysed, for which properties (safety, liveness, latency,
  availability), and with which methods (proof, model checking, analytical
  model, simulation, testbed)?
/ RQ2 (timing): Which Raft mechanisms depend on timing or clock assumptions,
  whether for safety or only for liveness, and how are those assumptions
  stated?
/ RQ3 (physics): Which models of distributed computation in relativistic
  spacetime exist, and which correctness results do they establish for
  consensus and replicated state machines?
/ RQ4 (gap): To what extent have clock-dependent mechanisms been analysed under
  relativistic or otherwise physically grounded models of time?

= Review method

== Protocol
The protocol was fixed before screening and follows PRISMA 2020 @page2021 for
reporting and Kitchenham and Charters @kitchenham2007 for conduct. It is
maintained alongside this article (`review/protocol.md`); deviations are
reported in @sec-validity.

== Sources and search strings
Scopus and Web of Science are the primary databases, complemented by IEEE
Xplore, the ACM Digital Library, dblp, and arXiv (cs.DC) for recent preprints.
Search strings combine a protocol block (Raft, state-machine replication) with
either a communication-model block or a physics-and-time block. The acronym
"RAFT" collides with a polymerisation technique and an optical-flow network,
so both are excluded explicitly. Full strings and narrowing rules are given in
the protocol.

== Snowballing
Database search is complemented by snowballing @wohlin2014. Backward snowballing
covers the reference lists of all included studies. Forward snowballing starts
from a seed set chosen because each seed is either foundational to the
relativistic strand or central to Raft's behaviour under non-ideal networks,
while having a citation count small enough to screen completely.
#todo[List seed set and iteration counts.]

== Eligibility and screening
#todo[Criteria summary; single-reviewer screening with blinded re-screen of a
20% sample and Cohen's κ.]

== Data extraction
For each included study we extract the communication model, the properties
analysed, the method, the timing mechanisms relied upon, any physical
parameters, and the principal result.

= Results
#todo[PRISMA flow diagram (figure). Mapping table for RQ1. Timing-dependence
table for RQ2. Synthesis for RQ3 and RQ4.]

= Discussion
#todo[Answers to RQ1–RQ4. Explicitly separate (i) results established in the
literature, (ii) consequences that follow directly from known models, and
(iii) open problems; the latter define the analytical phase.]

= Threats to validity <sec-validity>
#todo[Single reviewer; recency bias toward 2025–2026 preprints; known-item
seeding of the pilot search; database coverage of workshop venues.]

= Conclusion
#todo[Summary and research questions for the analytical phase.]

#bibliography("refs.bib", style: "ieee", title: "References")
