P1 | R17 | server/src/services/library.service.ts:346 | Prefix-only containment accepts an absolute uploadPath such as /allowed/../outside, permitting an external-library destination outside every importPath. | CONFIRMED
P1 | R17 | server/src/services/storage-template.service.ts:363 | Prefix-only root validation accepts a sibling path whose name begins with a space root (for example shared/family-2), so a template can place files outside that container tree. | CONFIRMED
P1 | I4 | server/src/cores/storage.core.ts:255 | A non-EXDEV rename failure is logged and returned rather than propagated, so relocation callers can continue and complete a relocation whose original file did not move. | CONFIRMED
P1 | I6 | server/src/services/storage-template.service.ts:275 | Template relocation catches and suppresses moveFile exceptions, after which AssetRelocationService completes the asset_relocation row despite the failed original move. | CONFIRMED
P2 | I4 | server/src/cores/storage.core.ts:274 | After an EXDEV copy verifies, old-path unlink failure is only logged before the new DB path and move-history deletion proceed, leaving the source copy outside the current container with no retry record. | CONFIRMED
P2 | I4 | server/src/cores/storage.core.ts:290 | Destination-only crash recovery cannot resume because verification unconditionally stats the already-missing old path before using assetInfo. | CONFIRMED
GAPS: Did not inspect relocation callers, repositories, schema, controllers, or tests; therefore could not verify transaction ordering, stack expansion, relocation-row path matching, authorization, or runtime retry behavior outside the assigned files.

REMEDIATION OUTCOME (Task 6, 16-Sep): all six CONFIRMED items FIXED — see AUDIT-FINDINGS.md P1–P2
table (commit `c0e236b76`; batch `Success` semantics reviewed as intended in Task 5). GAP narrowed:
move paths reviewed end to end (deleteSpace/library.delete tombstones, R10-02 checksum adoption,
R17-01 derived handling) with unit specs green in sandbox. Real crash/filesystem exercise still
needs a host (brief C7 demand) — open, host-owned.
