# Intent execution decision policy

Use this policy after gathering enough evidence to distinguish plausible interpretations. Do not use entropy alone as an oracle.

## Inputs

- `dominant_probability`: weight of the leading hypothesis.
- `normalized_entropy`: Shannon entropy divided by `ln(n)`, from 0 (concentrated) to 1 (uniform).
- `impact_divergence`: `low`, `medium`, or `high`; how differently competing hypotheses would change code, data, APIs, UX, security, or operations.
- `reversibility`: `easy`, `moderate`, or `hard`.
- `risk`: `low`, `medium`, or `high`, including migration, security, privacy, production, and user-facing risks.
- `evidence_conflict`: whether observed facts contradict the requested action or alleged cause.

## Default decision table

| Condition | Default gate |
|---|---|
| Evidence contradicts the requested action and the contradiction changes the intervention | `BLOCKED_BY_EVIDENCE` |
| Impact divergence is high and entropy is above 0.45 | `NEEDS_CLARIFICATION` |
| Risk is high or reversibility is hard, and the leading hypothesis is below 0.80 | `NEEDS_CLARIFICATION` |
| Leading hypothesis is at least 0.80, entropy is at most 0.45, and the action is low-risk and reversible | `READY` |
| Ambiguity remains but competing interpretations share the same safe first step | `READY_WITH_ASSUMPTIONS` |
| Evidence can cheaply resolve the ambiguity with a read-only measurement | Take that measurement, then reassess |

Thresholds are heuristics. Override them when the consequence model is clear, and record why.

## Question design

Ask one discriminating question whenever possible. Mention the fork it controls.

Good:

> “When you say the profile is inconvenient, is the priority reducing the number of steps to edit details, or improving the mobile layout? The first changes navigation; the second changes responsive UI.”

Avoid broad prompts such as “What do you mean?” or a long questionnaire.

If the user cannot answer, propose the smallest reversible experiment that yields evidence. Preserve alternative hypotheses in the IR.

## Sizing language

- Use exact counts only after tracing imports, callers, schemas, tests, generated artifacts, and migrations.
- Otherwise report `estimated N–M files`, name the confirmed core files, and list uncertainty drivers.
- State migrations separately: `none`, `possible`, or `required`.
- Do not translate file counts directly into time estimates without accounting for coupling, test depth, deployment constraints, and review.
