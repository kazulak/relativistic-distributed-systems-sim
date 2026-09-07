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

The causal chain of any lawful Raft replicated write consists of four sequential physical segments:

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

---

## 5. Verification Contract and Assertion Oracle

In the simulation suite:
1. For every client operation that completes with status `:committed`, the simulator computes:
   $$\text{margin} = (\tau_{\text{complete}} - \tau_{\text{invoke}}) - \Delta \tau_{\text{causal\_bound}}.$$
2. The assertion oracle enforces:
   $$\text{margin} \ge -\epsilon_{\text{numerical}}, \quad \epsilon_{\text{numerical}} = 4096 \cdot \varepsilon_{\text{Float64}} \approx 9.09 \times 10^{-13}.$$
3. A negative margin violating this threshold represents a critical simulator failure (superluminal information delivery or causality violation) and halts the experiment immediately.
