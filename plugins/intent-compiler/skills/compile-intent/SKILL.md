---
name: compile-intent
description: Compile vague, subjective, solution-biased, or causally uncertain product and software requests into an evidence-backed, verifiable Intent IR before planning or implementation. Use for requests such as “稍微优化一下”, “make it more premium”, “add search”, “the database is slow”, ambiguous bug reports, requirement clarification, change-impact estimation, or whenever different interpretations could lead to materially different code, data, API, security, UX, or operational changes.
---

# Compile Intent

Treat natural language as an observation of intent, not an executable instruction. Inspect the raw request and available evidence within the current task, separate the objective from the user's diagnosis or proposed implementation, sanitize sensitive material, and emit an Intent IR that a planner or coding agent can verify safely.

## Operating contract

- Keep the meaning of the observed request separate from its interpretation. Quote it verbatim only when it is free of secrets, personal data, and identifying metadata; otherwise emit a faithful redacted paraphrase.
- Preserve multiple plausible hypotheses until evidence distinguishes them.
- Treat probabilities as transparent evidence rankings, not calibrated truth.
- Distinguish `Problem`, `Cause Hypothesis`, and `Requested Action`.
- Ask only when unresolved ambiguity would materially change the action.
- Prefer read-only discovery before any implementation. Respect repository instructions and user-imposed scope.
- Minimize sensitive data: never emit credentials, tokens, private keys, cookies, personal contact details, user identifiers, machine names, or absolute home-directory paths. Use repository-relative paths and aggregate or redact log and analytics values.
- Never claim exact affected-file, migration, performance, or effort counts without tracing the relevant surfaces. Use a range and label it as an estimate when discovery is incomplete.
- If the user asked for implementation, continue from a `READY` or `READY_WITH_ASSUMPTIONS` IR into planning and coding. Do not stop merely to present the IR.

## Compile in passes

### 1. Capture the source

Record:

- the verbatim observed request for in-task reasoning only; sanitize it before placing it in Intent IR or any persisted artifact;
- explicit constraints, examples, deadlines, and forbidden changes;
- whether the user expressed a goal, symptom, feeling, cause hypothesis, requested action, or analogy.

Do not silently rewrite a symptom or proposed solution into the goal.

### 2. Expand the intent space

Generate 2–5 meaningfully different hypotheses. Prefer hypotheses that would lead to different interventions, such as usability, information architecture, latency, visual quality, conversion, reliability, accessibility, or stakeholder signaling.

For each hypothesis, state what evidence would support or falsify it. Avoid cosmetic variants of the same hypothesis.

### 3. Let the project constrain the language

Inspect evidence progressively, starting with the smallest relevant surface:

- repository instructions, architecture, routes, components, schemas, migrations, tests, analytics, and configuration;
- request paths, timings, logs, profiling data, and third-party boundaries when performance is alleged;
- accessible issue history, user feedback, recent changes, and product copy when available and in scope.

Record concrete locations and measurements internally. Separate observed facts from inference. Stop widening the search when additional discovery is unlikely to change the decision. Do not copy raw log lines, request payloads, account identifiers, or user feedback containing personal data into the IR.

### 4. Decompose the statement

Produce these distinct fields:

- `Problem`: the observable user or business cost;
- `Cause Hypothesis`: what the speaker believes causes the problem;
- `Requested Action`: the implementation they proposed;
- `Goal`: the outcome that should improve even if another implementation is chosen.

If a field is absent, mark it unknown rather than inventing it.

### 5. Run the literal counterfactual

Ask: “If the requested action were implemented exactly, would the evidence predict that the goal improves?”

Compare at least:

- literal implementation;
- strongest evidence-backed alternative;
- no-change or smallest-change baseline.

When evidence contradicts the user's cause hypothesis, preserve the goal and flag the conflict. Do not optimize a 37 ms query to solve a 2.4 s third-party wait.

### 6. Rank hypotheses and gate execution

Assign hypothesis weights totaling 1.0 and cite evidence for and against each. Use normalized Shannon entropy as a useful summary when there are at least two hypotheses:

`H = -sum(p * ln(p)) / ln(n)`

Read [decision-policy.md](references/decision-policy.md) when choosing whether to ask, execute, or take a bounded investigative step. Resolve every bundled reference and script relative to the directory containing this `SKILL.md`. For machine-readable IR, use [intent-ir.schema.json](references/intent-ir.schema.json) and validate it with:

```powershell
python <skill-directory>/scripts/intent_ir.py validate <intent-ir.json>
python <skill-directory>/scripts/intent_ir.py assess <intent-ir.json>
```

Choose one gate:

- `READY`: evidence supports a clear, verifiable interpretation.
- `READY_WITH_ASSUMPTIONS`: uncertainty remains, but the assumptions are explicit and the action is low-risk and reversible.
- `NEEDS_CLARIFICATION`: plausible interpretations require materially different actions and evidence cannot choose safely.
- `BLOCKED_BY_EVIDENCE`: the requested action conflicts with observed facts or the evidence required to proceed is unavailable.

If clarification is necessary, ask the smallest discriminating question and explain what decision it controls. Do not ask for information that repository evidence can answer.

### 7. Sanitize the output boundary

Before emitting or saving Intent IR, perform a privacy pass:

- replace secrets and authentication material with `[REDACTED_SECRET]` and never preserve enough characters to reconstruct them;
- replace personal names, email addresses, phone numbers, account IDs, IP addresses, device names, and unique user identifiers with stable local placeholders such as `[PERSON_1]` or `[USER_ID_1]` only when identity is relevant; otherwise omit them;
- convert absolute filesystem paths to repository-relative paths; if a path is outside the repository, describe only its role, such as `[USER_CONFIG]/marketplace.json`;
- summarize logs, analytics, issue text, and user feedback instead of quoting raw records; use aggregate measurements when individual records are unnecessary;
- omit timestamps and location metadata unless they are required to decide the intent, and reduce required timestamps to the least precise useful granularity;
- scan every human-readable and JSON field, including evidence, constraints, assumptions, conflicts, source locations, and verification steps—not only `observed_request`.

If redaction would remove evidence required for a safe decision, state that sensitive evidence was inspected but omitted and use `BLOCKED_BY_EVIDENCE` or ask for a privacy-safe substitute. Never weaken redaction merely to make the IR more detailed.

### 8. Emit Intent IR

Return a compact human-readable IR unless the user requests JSON. Include:

```text
Intent IR
Status: READY | READY_WITH_ASSUMPTIONS | NEEDS_CLARIFICATION | BLOCKED_BY_EVIDENCE

Observed Request
<privacy-safe paraphrase, or verbatim only when safe>

Goal
<outcome, not implementation>

Problem / Cause Hypothesis / Requested Action
<kept distinct>

Evidence
- <sanitized fact, aggregate measurement, or repository-relative source location>

Competing Hypotheses
- H1 <weight>: <interpretation>; for: <evidence>; against: <evidence>

Constraints / Non-goals / Assumptions
<explicit boundaries>

Conflicts
<language-versus-evidence contradictions, or none>

Uncertainty
<normalized entropy plus a plain-language explanation>

Success Criteria
- <observable and testable outcome>

Affected Surface
- Confirmed: <files, modules, schemas, APIs>
- Estimated: <range and reason>
- Data migration: none | possible | required

Execution Gate
<decision, why, and the single question if needed>

Verification Plan
- <how to prove both implementation and intent>
```

See [examples.md](references/examples.md) for full examples and [intent-ir.schema.json](references/intent-ir.schema.json) for the JSON contract.

## Continue through the closed loop

When implementation is in scope:

1. Plan and implement against `Goal`, `Constraints`, and `Success Criteria`, not merely the raw wording.
2. Verify code behavior with the relevant tests, measurements, or UI checks.
3. Re-read the observed request and compare the actual change with every success criterion.
4. Report two independent verdicts:
   - `Implementation Correct`: the change matches the plan and passes technical verification.
   - `Intent Correct`: evidence indicates the original human problem improved.
5. If implementation is correct but intent is not, do not call the task successful. Reopen intent resolution with the new evidence.

Keep the IR proportional: a small reversible change may need only a brief inline IR; a cross-cutting or high-risk change deserves the full structure.
