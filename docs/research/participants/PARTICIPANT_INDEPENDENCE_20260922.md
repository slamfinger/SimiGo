# Participant / Knowledge-Source Independence Assessment — 2026-09-22

## Purpose

验证现有 SimiGo-Lab 研究材料是否包含真正独立的信息渠道，而不是因为研究主题、文件或参与者名称不同就把同一证据算作多条证据。

## Candidate channels

| Channel | Observation object | Data / source | Method | Current status |
|---|---|---|---|---|
| C1 Official API/source audit | upstream public semantics | pinned MLX / MLXLMCommon source | source inspection / API inventory | **independence candidate** |
| C2 Runtime evidence | integrated SimiGo behavior | production binary, traces, runtime telemetry | real-device execution | **independence candidate** |
| C3 F0 controlled experiment | execution-state fork behavior | measured fork artifacts + real-device run | controlled experiment + source cross-check | **partially independent** |
| C4 Historical architecture audit | local runtime authority / simplification | SimiGo audit + deletion records | architectural review | **not yet proven independent from C2** |

## Independence test

The relevant test is:

> If another channel were removed, could this channel independently obtain the same proposition from its own observation object, source, method, and reasoning path?

### C1 vs C2

These have different observation objects and sources:

- C1 asks what the upstream public API exposes.
- C2 asks what the integrated SimiGo runtime actually does.

They therefore have a meaningful independence basis, although they can still share interpretation.

### C1 vs C3

C3 contains an empirical execution component, while C1 is primarily source/API inspection. The methods differ.

However, F0 also uses source inspection as part of its decision matrix. Therefore C3 must not be counted as wholly independent from C1; its empirical component is independent evidence, while its API-coverage component overlaps C1.

### C2 vs C4

C4 is an architectural review of SimiGo runtime authority and historical deletions. Much of its evidence originates from the same runtime failures, traces, and implementation history that informed C2.

**Therefore C4 is not currently accepted as an independent channel.**

### C3 empirical component vs C2

The F0 controlled run can be treated as a distinct experimental observation when the exact run artifact and protocol are preserved. But the conclusion must remain bounded by the tested model, dependency pins, and hardware.

## Current conclusion

As of 2026-09-22:

- There are **at least two defensible evidence families**: upstream public-source/API evidence (C1) and direct real-device/runtime evidence (C2).
- F0 contributes an additional controlled experimental observation, but its source-audit portion overlaps C1.
- Historical architectural audit material should currently be treated as corroborating analysis, **not** as a third independent knowledge source.

No claim of "four independent participants/channels" is justified by the present record.

## Remaining work

1. Preserve exact F0 run artifacts and environment metadata.
2. Separate experimental observations from source-derived interpretation in future records.
3. For each research question, pre-register which channels are expected to be independent before synthesis.
4. Do not count a lesson, audit, benchmark, and conclusion as separate evidence merely because they are separate files.
