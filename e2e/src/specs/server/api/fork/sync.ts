// Fork sync helpers (shared-libraries, T0). See TESTING.md §4.
//
// Reads POST /sync/stream JSON-lines into typed events. Full ack-token
// pagination semantics stay with S6; ackAll() drains the stream until it is
// quiet (bounded), which is enough for the world smoke and record-sync.

import { SyncRequestType } from '@immich/sdk';
import request from 'supertest';
import { app } from 'src/utils.js';

export interface SyncEvent {
  type: string;
  [key: string]: unknown;
}

const allTypes = Object.values(SyncRequestType);

export const readSync = async (
  accessToken: string,
  types: SyncRequestType[] = allTypes,
  timeoutMs = 0,
): Promise<SyncEvent[]> => {
  // Note: ackAll() below never observes quiet (it posts no acks, so every pass
  // returns the full backfill). Prefer a targeted readSync + explicit assertions.
  // The stream answers `application/jsonlines+json`, which superagent tries to
  // JSON.parse as one document and chokes on; collect the raw text instead.
  const pending = request(app)
    .post('/sync/stream')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ types })
    .buffer(true)
    .parse((res, callback) => {
      let text = '';
      res.on('data', (chunk: Buffer) => {
        text += chunk.toString();
      });
      res.on('end', () => callback(null, { text }));
    });
  const response = await (timeoutMs > 0 ? pending.timeout(timeoutMs) : pending);
  const { status } = response;
  const text = (response.body as { text?: string }).text ?? response.text ?? '';
  if (status !== 200) {
    throw new Error(`sync stream failed with status ${status}: ${text.slice(0, 200)}`);
  }
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line) as SyncEvent);
};

/** Drain the stream until a pass returns no events (bounded by maxPasses). */
export const ackAll = async (accessToken: string, maxPasses = 10): Promise<SyncEvent[]> => {
  const seen: SyncEvent[] = [];
  for (let pass = 0; pass < maxPasses; pass++) {
    const events = await readSync(accessToken);
    seen.push(...events);
    if (events.length === 0) {
      return seen;
    }
  }
  throw new Error(`sync stream not quiet after ${maxPasses} passes`);
};
