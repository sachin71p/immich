# S1 verify — 2026-09-14

1. `cd server && pnpm run check` → PASS
2. `cd server && pnpm run lint` → PASS
3. `cd server && pnpm run test` → FAIL — 34 controller spec files / 226 tests failed
   (for example, `ActivityController > GET /activities > should require an albumId`;
   all share the same environment-level error):
   ```
   TypeError: Cannot read properties of null (reading 'port')
   Serialized Error: { code: 'EPERM', errno: -1, syscall: 'listen', address: '0.0.0.0' }
   Error: listen EPERM: operation not permitted 0.0.0.0
   ❯ Server.listen node:net:2178:7
   ❯ Test.serverAddress ../node_modules/.pnpm/supertest@7.2.2.../lib/test.js:63:35
   ```
   Summary: 71 passed; 34 failed; 2046 passed; 226 failed; 1 expected fail.
4. `cd server && pnpm run test:medium -- test/medium/specs/repositories/shared-libraries-schema.spec.ts` → NOT RUN (stopped after step 3 failure).
