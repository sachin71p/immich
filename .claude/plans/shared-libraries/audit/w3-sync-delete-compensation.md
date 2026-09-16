P0 | PERM-11 | server/src/repositories/sync.repository.ts:923 | No scoped code provides a reliable post-removal SharedSpaceDeleteV1: container deletes read shared_space_audit, while member removal only deletes shared_space_member and member-delete delivery still requires a current membership. | SUSPECTED
GAPS: Library removal has a potential compensating SharedLibraryDeleteV1 path (library_member_audit filtered by the removed user at sync.repository.ts:1152-1156 and emitted at sync.service.ts:769-772), but I could not inspect the audit-trigger producer or client delete handler within the permitted scope; the same trigger limitation prevents confirming whether shared_space_audit is populated on member deletion.

REMEDIATION OUTCOME (Task 6, 16-Sep): GAP CLOSED — both trigger producers verified in migration
`1789426700279` (member-delete writes user-keyed rows; cascade skips via depth guard, which is why
container deletion needed explicit tombstones, commit `d93fc777d`); Apple client handlers verified
(spaceDelete/spaceMemberDelete/libraryDelete all drop assets + membershipLoss fixture). The
SUSPECTED :923 path works for member removal — see P0 NOT-A-DEFECT rows.
