// Fork sync recorder (shared-libraries, T0). See TESTING.md §4.
//
// Records one sync stream per world user into
// native-apple/PhotosCore/Tests/Fixtures/world/*.jsonl so the Apple tier
// fixtures stay in lockstep with the server world. Run after buildWorld()
// with the e2e stack up; a no-op (with a notice) when the stack is down.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { readSync } from './sync.js';
import type { World } from './world.js';

export const appleWorldDir = join(
  import.meta.dirname,
  '..',
  '..',
  '..',
  '..',
  '..',
  '..',
  'native-apple',
  'PhotosCore',
  'Tests',
  'Fixtures',
  'world',
);

export const recordWorldSync = async (world: World): Promise<string[]> => {
  mkdirSync(appleWorldDir, { recursive: true });
  const written: string[] = [];
  for (const [name, user] of Object.entries(world.users)) {
    const events = await readSync(user.login.accessToken);
    const file = join(appleWorldDir, `${name}.jsonl`);
    writeFileSync(file, `${events.map((e) => JSON.stringify(e)).join('\n')}\n`);
    written.push(file);
  }
  return written;
};
