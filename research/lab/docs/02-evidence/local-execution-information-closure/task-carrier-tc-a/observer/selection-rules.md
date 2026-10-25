# Observer Selection Rules

The observer acts only after Execution A stops. The observer is not a Runtime
component and must not create semantics.

## 1. Preserve first

Preserve all Execution A artifacts before selection:

```text
A prompt;
all requests;
all responses;
tool calls;
tool results;
final answer;
Runtime trace excerpt;
file read evidence.
```

## 2. Eligible Candidate Information

The only eligible Candidate Information is Execution A's final answer when it
is structurally complete:

```text
valid JSON;
`register_version` present;
all four source files reflected through the three service records;
all three unordered pairs present;
each service and pair has a boolean decision and an issues array.
```

The observer may check structure but must not judge semantic correctness as a
store precondition. Semantic correctness is scored after Execution B.

## 3. Packaging is verbatim selection

If eligible, the observer may copy Execution A's exact final answer into:

```text
candidate-information.json
```

The bytes must be the exact final-answer string. The observer must not:

```text
repair JSON;
normalize whitespace;
summarize;
add conclusions;
add source content;
convert Runtime trace/cache into Information;
create a new schema.
```

If the final answer is absent, malformed, incomplete, or cannot be selected
verbatim, do not store anything. Record `R-A0` or `R-A1` according to the
charter.

## 4. Store and record

If selection succeeds:

```bash
t4ctl store --db <Information₀-copy> --file candidate-information.json
```

Record:

```text
exact Stored Information identity;
SHA-256 of candidate-information.json;
database SHA-256 before and after store;
t4ctl stdout;
selection rationale.
```

The identity is then the only A-derived item handed to Execution B.
