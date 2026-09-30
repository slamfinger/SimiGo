# SimiGo-Lab — Execution State Reuse Cross-Session Context Capsule

Date: 2026-09-30
Purpose: preserve research context that cannot safely be reconstructed by reading isolated documents alone.

## A. Origin story

SimiGo did not begin from a top-down architecture proposal.

The recurring pattern is:

engineering fact
→ concrete problem
→ experiment
→ unexpected boundary
→ abstraction
→ contract
→ engineering validation.

The original fork line was:
MLX lacked fork capability
→ engineering need
→ session/KV/release/restore problems
→ logical vs physical boundary
→ Execution State.

The current reuse line intentionally follows the same method:
Representation disappears
→ why must computation return to cold prefill?
→ test whether State survived
→ test whether surviving State can be re-materialized
→ only then derive higher-level storage/retrieval/reuse architecture.

## B. Current intellectual question

The important question is NOT:
“How do we build PALACE?”

It is:
“Is Execution State itself a reusable computational asset whose lifecycle can exceed a particular Physical Representation?”

PALACE becomes important only if this premise is supported.

## C. Current hypothesis tree

H0: Cold prefill is inherent; loss of Representation implies recomputation from semantic history.

H1: Execution State survives Representation loss and can produce a new Representation without full cold prefill.

H2: The State can be rebound across runtime lifetimes.

H3: A surviving State can be taken over by another backend.

H4: Such States can be persistently stored and efficiently retrieved.

H5: State rematerialization can be materially cheaper than recomputing the same computation from history.

Only H0/H1 are directly at issue in ES-R1. Later hypotheses must not be assumed.

## D. Why this may become a paper

The research value is not the claim of “huge speedup” in advance.

The potentially novel chain is:
- an ordinary representation-loss problem exposes a deeper state boundary;
- the state/representation lifecycle relationship is experimentally tested;
- a State that outlives its representation changes the unit of reuse from cache/representation toward computation state;
- backend takeover, persistence, retrieval, and economics can then be tested as separate consequences.

If the chain fails, the negative boundary is still scientifically useful.

## E. Existing evidence that precedes this track

PALACE-1 E0-E3 is sealed/parked.

Observed before this track:
- checkpoint and Prefix Pool are replaceable physical representations;
- conversation history carries observed continuation semantics in the tested workload;
- Prefix Pool is an acceleration representation, not the observed continuation nucleus;
- restore dependency and continuation dependency differ;
- semantic absence can produce plausible but ungrounded continuation rather than an automatic runtime failure.

These are bounded workload observations, not universal theorems.

Execution State Architecture Contract v1.0 is the upstream semantic reference.
BACKEND-1 seam work is registered but does not prove State Reuse.

## F. Current experiment chain

ES-R1:
Representation Loss → State Reuse
Question: can the same State be reused without full history/full cold prefill?

ES-R2:
Backend Takeover
Question: can another backend take over an existing State when the original representation is unavailable?

ES-R3:
Persistence/Lifetime
Question: can the State survive runtime/process lifetime boundaries?

ES-R4:
Retrieval
Question: can a useful State be found reliably from a larger State space?

ES-R5:
Economics
Question: when does storing/rematerializing State beat recomputation?

PALACE:
potential system-level storage/retrieval/reuse layer, only after the underlying semantic premise is evidenced.

## G. Current agent boundary

The local coding agent is an executor, not the research authority.

Assistant/research architect:
- fixes the research question;
- locks experiment design;
- determines gates;
- reviews evidence;
- decides whether a hypothesis is supported;
- authorizes the next phase.

Local agent:
- inspects code;
- builds test harnesses;
- runs experiments;
- records raw evidence;
- implements only explicitly authorized minimal changes;
- does not redefine the research question or silently widen scope.

No implementation is considered evidence merely because tests compile/pass.

## H. Cross-session recovery rule

When opening a new session, first recover in this order:

1. This Context Capsule
2. ES Reuse Research Master
3. current experiment design
4. latest Research Record / raw evidence
5. current git branch and commit
6. only then inspect source code as needed.

The new session must reconstruct:
- why the experiment exists;
- what is proven;
- what is unknown;
- which gate is open;
- what the local agent was authorized to do;
- what must NOT be changed.

Reading documents without restoring this causal context is insufficient.

## I. Security boundary

Research is internal.
Use only synthetic/authorized state.
Do not publish concrete recovery procedures, sensitive persistence combinations, isolation-bypass methods, or information that could enable access to another person's state.

Governance authority and content authority must remain conceptually separate.
