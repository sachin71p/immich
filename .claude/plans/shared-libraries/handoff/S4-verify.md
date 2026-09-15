# S4 verify — 2026-09-14

1. `cd server && pnpm run check` → PASS
2. `pnpm run lint` → PASS
3. `pnpm run test` → FAIL — test environment cannot bind `0.0.0.0` (226 failures across 34 controller test files; not a phase-specific assertion failure).

First relevant error:
```
Error: listen EPERM: operation not permitted 0.0.0.0
 ❯ Server.setupListenHandle [as _listen2] node:net:1994:21
 ❯ Server.listen node:net:2178:7
 ❯ Test.serverAddress .../supertest/lib/test.js:63:35
```

Stopped at the first failing prescribed step; `test:medium` and OpenAPI/client diff stat were not run.
