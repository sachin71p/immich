P1 | I3 | server/src/repositories/asset.repository.ts:818 | findLivePhotoMatch filters only owner/type/CID, not spaceId or libraryId, so it can link live-photo halves from different containers | CONFIRMED
P1 | I3 | server/src/services/metadata.service.ts:726 | Extracted motion assets copy libraryId but omit a source spaceId, placing a shared-space live-photo half in the personal container | CONFIRMED
P1 | I6 | server/src/services/asset-media.service.ts:179 | Shared upload writes spaceId directly and queues metadata extraction only, without creating an asset_relocation row in the insert path | CONFIRMED
P1 | I6 | server/src/schema/migrations/1789426700279-SharedLibraries.ts:112 | The space FK ON DELETE SET NULL can change an asset container without an asset_relocation row or relocation trigger | CONFIRMED
P1 | I7 | server/src/schema/tables/asset.table.ts:102 | Schema enforces only space/library exclusivity and has no DB CHECK preventing Locked visibility on a shared container, leaving I7 service-only | CONFIRMED
GAPS: I1 is both (DB CHECK plus scoped writers set exclusive targets); I2 is DB-enforced by owner FK and scoped writers preserve owner; I3 is neither DB-enforced nor fully service-enforced; I4 physical-path enforcement and I5 Flutter compatibility are outside this axis; I6 is DB/service for moveWithRelocation but the two confirmed write paths bypass its relocation-row rule; I7 is service-only; no tests run per brief.

REMEDIATION OUTCOME (Task 6, 16-Sep): all five CONFIRMED items FIXED — see AUDIT-FINDINGS.md P1–P2
table (commits `d2f0b7de6`, `2951462e2`, `654e37c9f`). I7 DID gain a DB CHECK (amendment +
table mirror + medium tests). I3 stays service-level by decision: all writers go through the
single `findLivePhotoMatch` choke point (now container-scoped) and motion creation carries the
container; a DB trigger on the self-FK link is deferred as disproportionate (no owner assigned —
flag for S10 if wanted). I6 bypasses closed via relocation rows + RESTRICT FK.
