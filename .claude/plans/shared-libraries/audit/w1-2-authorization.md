P0 | PERM-01-nonmember | server/src/utils/access.ts:119 | AssetRead/View/Download retain upstream partner access before space membership, and the partner query has no spaceId exclusion, so a nonmember partner can read a contributor's timeline/hidden space asset. | CONFIRMED
P0 | PERM-04-nonmember | server/src/utils/access.ts:135 | AssetShare likewise grants a nonmember partner of the owner access to a space asset, allowing it to be added to a shared link contrary to the nonmember rule. | CONFIRMED
P0 | PERM-11 | server/src/repositories/access.repository.ts:699 | A removed contributor who owns a space person still passes the owner OR branch without current shared_space_member membership and can retain person read/update access. | CONFIRMED
P0 | PERM-11 | server/src/repositories/access.repository.ts:727 | A removed contributor who owns an asset still passes the asset-owner OR branch for its space asset's faces without current membership and can retain face access. | CONFIRMED
P0 | PERM-08-contributor | server/src/utils/access.ts:306 | SharedSpaceMemberUpdate is granted to every member while the ownership-transfer controller uses that permission, so a contributor transfer block depends on an uninspected service-layer guard. | SUSPECTED
P1 | PERM-07-owner | server/src/utils/access.ts:308 | SharedSpaceMemberDelete is granted to every member and backs the generic remove-member route, so preventing an owner from leaving/removing itself depends on an uninspected service-layer guard. | SUSPECTED
P3 | PERM-01-contributor | server/src/utils/access.ts:146 | AssetFileDownload checks only asset-file owner access even though its controller serves file contents, denying space/library contributors the promised download right through this endpoint. | CONFIRMED
P3 | PERM-03-contributor | server/src/utils/access.ts:197 | AssetEditGet remains owner-only while AssetEditCreate/Delete admit space/library members, so contributors can edit but cannot retrieve the existing edit state. | CONFIRMED
GAPS: Did not inspect services, DTO/API-key validation, auth middleware, or tests because they are outside the assigned file scope; therefore service-layer owner/self-removal and API-key enforcement could not be confirmed.

REMEDIATION OUTCOME (Task 6, 16-Sep): GAP CLOSED for owner/self-removal — service guards verified
(`shared-space.service.ts:129-154`, Timeline DTO; library member admin stays admin-only). All P0
items FIXED (see AUDIT-FINDINGS.md P0 table, commits `4337fe52a`, `7b77c2860`); both P3s FIXED
(see Task 4 section, commit `914d25258`); both SUSPECTED member-guard items NOT-A-DEFECT (see
Task 4 section). API-key enforcement untested — still open (not fork-specific; no owner assigned).
