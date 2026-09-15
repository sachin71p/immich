// Fork per-user clients + status assertions (shared-libraries, T0). See TESTING.md §4.
//
// as(user) returns SDK calls bound to that user's token. Status-sensitive
// calls (where T1 asserts 403/400) go through supertest so the status is
// observable — the generated SDK client throws on non-2xx.

import { getAssetInfo, moveAssets, type AssetMoveDto, type AssetMoveResponseDto } from '@immich/sdk';
import request from 'supertest';
import { app } from 'src/utils.js';
import type { WorldUser } from './world.js';

const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

export interface ForkClient {
  token: string;
  getAsset: (id: string) => Promise<unknown>;
  moveAssetsRaw: (dto: AssetMoveDto) => request.Test;
}

export const as = (user: WorldUser): ForkClient => {
  const token = user.login.accessToken;
  return {
    token,
    getAsset: (id: string) => getAssetInfo({ id }, { headers: auth(token) }),
    moveAssetsRaw: (dto: AssetMoveDto) =>
      request(app).post('/assets/move').set('Authorization', `Bearer ${token}`).send(dto),
  };
};

export const moveAssetsAs = async (user: WorldUser, dto: AssetMoveDto): Promise<AssetMoveResponseDto> =>
  moveAssets({ assetMoveDto: dto }, { headers: auth(user.login.accessToken) });

export const expectStatus = (status: number, expected: number, body: unknown): void => {
  if (status !== expected) {
    throw new Error(`expected status ${expected}, got ${status}: ${JSON.stringify(body).slice(0, 500)}`);
  }
};

export const expect403 = async (call: Promise<{ status: number; body: unknown }>): Promise<void> => {
  const response = await call;
  expectStatus(response.status, 403, response.body);
};
