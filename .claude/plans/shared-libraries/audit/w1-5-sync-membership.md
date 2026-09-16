P0 | PERM-11 | server/src/repositories/sync.repository.ts:977 | A removed space member cannot receive SharedSpaceMemberDeleteV1 because the delete stream requires a current shared_space_member row for the recipient. | CONFIRMED
P0 | PERM-11 | server/src/repositories/sync.repository.ts:1032 | A removed space member cannot receive SharedSpaceAssetRemoveV1 for that space because the asset-removal stream also requires their now-deleted membership row. | CONFIRMED
P0 | - | server/src/repositories/sync.repository.ts:1172 | A removed library member cannot receive per-asset SharedLibraryAssetRemoveV1 events because the removal stream requires their now-deleted library_member row. | CONFIRMED
GAPS: Did not inspect database audit triggers or client-side handling of SharedSpaceDeleteV1/SharedLibraryDeleteV1, so I could not determine whether a separate container-delete event compensates for the suppressed member/asset removals.

REMEDIATION OUTCOME (Task 6, 16-Sep): GAP CLOSED — triggers verified in the migration
(member-delete writes user-keyed audit rows), delivery verified by medium SY-03/04/05, client
drop verified in Apple code + membershipLoss fixture. All three CONFIRMED items NOT-A-DEFECT —
see AUDIT-FINDINGS.md P0 table. Companion fix: container-deletion tombstones (commit `d93fc777d`).
