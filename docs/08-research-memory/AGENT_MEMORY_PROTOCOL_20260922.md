# Agent Memory Protocol

**Purpose:** 让不同本地 Agent、ChatGPT 以及未来研究参与者共享一个可恢复、可审计、不会污染正式状态的研究记忆库。

## 1. Three-layer memory model

```
A. AUTHORITATIVE STATE
   RESEARCH_STATE + endpoint / closure + ledger + Git history
                ↓
B. RESEARCH MEMORY
   durable insights / hypotheses / forks / dead ends / open questions
                ↓
C. DIALOGUE
   local Agent ↔ ChatGPT ↔ human discussion
```

The layers are intentionally asymmetric:

- State can constrain memory.
- Memory can propose future questions.
- Dialogue can create candidate memory.
- Dialogue must never silently mutate State.

## 2. What a new Agent must read

### Fast recovery

1. `docs/RESEARCH_STATE.md`
2. `docs/00-governance/RESEARCH_PROGRAM_REGISTER_20260922.md`
3. `docs/00-governance/RESEARCH_DEPENDENCY_MAP_20260922.md`
4. current endpoint / closure for the active line
5. `docs/RESEARCH_MEMORY.md` when conceptual history matters

### Before touching experiments

Also read:

6. `docs/00-governance/EXPERIMENT_REGISTER_20260922.md`
7. `docs/00-governance/NEGATIVE_AND_OPEN_QUESTIONS_REGISTER_20260922.md`
8. the specific design / evidence / decision documents

### Before changing architecture

Also read:

9. `docs/00-governance/ARCHITECTURE_CONSEQUENCE_MAP_20260922.md`
10. the relevant architecture constraints and source design documents

## 3. Memory item schema

Every durable memory item should have:

- stable ID;
- concise title;
- origin date / provenance;
- type: insight / hypothesis / fork / dead-end / open-question / process;
- status;
- scope;
- supporting anchors;
- forbidden inference;
- promotion path, if any.

Example:

```text
RM-XXX
Type: ARCHITECTURE_HYPOTHESIS
Status: CANDIDATE
Scope: ...
Evidence: ...
Forbidden inference: ...
Promotion: Memory → Definition → RQ → Evidence → Decision
```

## 4. Agent handoff protocol

An Agent ending a work session should leave enough repository state for another Agent to resume without the original conversation:

```
What changed
    ↓
Why it changed
    ↓
Evidence / review
    ↓
Current state
    ↓
Next legal action
    ↓
Forbidden actions
```

Do not rely on “I told the other Agent in chat”.

## 5. Review / proposal separation

A memory entry may record that an Agent proposed or reviewed something, but it must preserve:

```
proposal ≠ review
review ≠ registration
registration ≠ result
result ≠ architecture authorization
```

## 6. Shared-bus principle

GitHub is the durable asynchronous exchange layer between local Agents and ChatGPT. It should carry structured, provenance-bearing artifacts rather than raw conversational transcripts.

A future `docs/research_bus/` may be introduced if volume justifies it. Until then, this protocol plus Git commits provide the minimum shared memory substrate.

## 7. Conflict resolution

When Agents disagree:

1. current repository state wins over conversation;
2. newer authoritative commit wins over stale memory;
3. endpoint/closure scope wins over informal interpretation;
4. unresolved disagreement becomes an explicit open question or review record;
5. no Agent silently edits historical evidence to resolve a disagreement.

## 8. Memory integrity rule

A memory library is successful only if a new Agent can answer, from the repository alone:

- Where are we?
- What has been proved?
- What has not been proved?
- What has been closed?
- What has failed or been ruled out?
- What ideas are still candidates?
- What is the next legal action?
- What must not be done?

If the repository cannot answer these without reconstructing old chat, the memory layer is incomplete.
