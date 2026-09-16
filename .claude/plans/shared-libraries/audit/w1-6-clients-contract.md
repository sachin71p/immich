P1 | I7 | web/src/lib/components/asset-viewer/AssetViewerNavBar.svelte:203 | Space/library members satisfy the broadened isOwner gate and are offered SetVisibilityAction, which submits visibility=Locked for a container asset despite I7. | CONFIRMED
P3 | I5 | open-api/immich-openapi-specs.json:14930 | The shared-space updateMyTimeline operationId duplicates the external-library operation at line 7922 while their request DTOs differ, leaving generated SDK operation identity ambiguous. | CONFIRMED
GAPS: Did not inspect server endpoint implementations or generated Dart/Swift SDK output because they are outside this axis's permitted scope; S10's documented pending OpenAPI/SDK regeneration was not re-reported.

REMEDIATION OUTCOME (Task 6, 16-Sep): I7 web item FIXED (UI gate + clean server 400, see
AUDIT-FINDINGS.md P1–P2 table, commit `441294e6c`); server endpoints verified (400s in
`update`/`updateAll` + CHECK). opId item DEFERRED to S10 regen with rename prescription (see
Task 4 section). TS SDK inspected (ambiguous suffixes confirmed); Dart/Swift regen still
S10-owned — open.
