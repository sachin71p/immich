P0 | PERM-11 | server/src/repositories/access.repository.ts:246 | Asset owner access treats every asset with spaceId NULL as personal without excluding libraryId, so a removed external-library contributor retains direct access to owned library assets. | CONFIRMED
P0 | PERM-11 | server/src/repositories/access.repository.ts:274 | Partner access joins every timeline/hidden asset owned by the partner without requiring both spaceId and libraryId to be NULL, exposing partner space and external-library assets outside §10 scope. | CONFIRMED
P0 | PERM-11 | server/src/repositories/access.repository.ts:351 | Asset-file owner access checks only ownerId and lock state, so an ex-space or ex-library contributor can download files from an owned asset after membership removal. | CONFIRMED
P0 | PERM-11 | server/src/repositories/memory.repository.ts:73 | Memory search returns all linked timeline assets for a caller-owned memory with no current container-membership predicate, preserving removed members' access to previously generated space memories. | CONFIRMED
P0 | PERM-11 | server/src/repositories/memory.repository.ts:192 | Single-memory retrieval repeats the unscoped linked-asset query, so MemoryRead can expose stale space/library assets after membership removal. | CONFIRMED
P3 | R16 | server/src/repositories/asset.repository.ts:960 | Timeline serialization reports favorites to non-owner space viewers but omits libraryId, so eligible external-library members receive false for a globally favorited asset. | CONFIRMED
GAPS: Did not inspect callers outside the assigned repository/service scope (including ContainerScopeService, controllers, and calendar-heatmap callers), so endpoint reachability and scope-resolver fallback behavior were not independently checked.

REMEDIATION OUTCOME (Task 6, 16-Sep): all six CONFIRMED items FIXED — see AUDIT-FINDINGS.md P0 table
(PERM-11 predicate + partner scoping, commit `4337fe52a`) and Task 4 R16 favorites fix (commit
`2951462e2`). GAP narrowed: ContainerScopeService read during Task 1; service wiring covered by
mock-based unit specs (green in sandbox). Full endpoint reachability still needs the host e2e run.
