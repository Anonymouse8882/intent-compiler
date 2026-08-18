# Intent IR examples

## “Add search”

```text
Intent IR
Status: READY_WITH_ASSUMPTIONS

Observed Request
“这里加个搜索吧。”

Goal
Reduce the time needed to find a historical order.

Problem / Cause Hypothesis / Requested Action
Problem: Users cannot quickly locate older orders.
Cause Hypothesis: The order list lacks a direct retrieval mechanism.
Requested Action: Add a search field.

Evidence
- The screen exposes 200 orders in a flat, paginated list.
- Existing API supports date, status, and order-ID filters.
- No product analytics were available to identify the most common lookup key.

Competing Hypotheses
- H1 0.60: Users know an order ID and need direct lookup.
- H2 0.25: Users browse by recency or status.
- H3 0.15: The real issue is slow page-by-page navigation.

Success Criteria
- A known order can be reached in at most two interactions.
- Existing list and pagination behavior remain intact.

Affected Surface
- Confirmed: order-list UI, filter state, API client, tests.
- Estimated: 4–7 files.
- Data migration: none.

Execution Gate
Implement order-ID lookup using the existing filter API as the smallest reversible step. Preserve date/status filtering as an alternative if usage evidence changes the ranking.
```

## “Optimize the database”

```text
Intent IR
Status: BLOCKED_BY_EVIDENCE

Observed Request
“后台加载有点慢，优化一下数据库。”

Goal
Reduce time before the admin screen becomes usable.

Problem / Cause Hypothesis / Requested Action
Problem: Admin users wait too long for the page.
Cause Hypothesis: Database queries are slow.
Requested Action: Optimize the database.

Evidence
- Database span: 37 ms p50.
- Third-party enrichment call: 2.4 s p50.
- Rendering and remaining server work: 180 ms p50 combined.

Conflicts
The requested cause is not the dominant measured bottleneck.

Success Criteria
- Reduce p50 usable-page latency from 2.7 s to under 1.0 s.
- Preserve enrichment correctness or expose an explicit deferred state.

Execution Gate
Do not change indexes or queries. Investigate deferring, caching, or timing out the third-party enrichment call.
```

## “Slightly optimize the homepage”

Do not report “14 files and one migration” merely because the phrase sounds broad. Trace the homepage route, composed sections, shared design tokens, data contracts, tests, analytics events, and schema changes first. Then report confirmed files separately from the estimated total and explain why any migration is required.
