// fork: shared-libraries
// Computes the allowed "Move to…" destinations for a selection of assets, per DECISIONS §6
// (move rules R4, R5, R10): personal only if every selected asset is owned by the acting user;
// any shared space the user is a member of; any external library where the user is owner/member
// AND an upload path is configured.
import type { SharedLibraryResponseDto, SharedSpaceResponseDto } from '@immich/sdk';

export type MoveTarget =
  | { type: 'personal' }
  | { type: 'space'; id: string; name: string }
  | { type: 'library'; id: string; name: string };

export const computeMoveTargets = (
  selectedAssets: { ownerId: string }[],
  myUserId: string,
  spaces: SharedSpaceResponseDto[],
  libraries: SharedLibraryResponseDto[],
): MoveTarget[] => {
  const targets: MoveTarget[] = [];

  const allMine = selectedAssets.length > 0 && selectedAssets.every((asset) => asset.ownerId === myUserId);
  if (allMine) {
    targets.push({ type: 'personal' });
  }

  for (const space of spaces) {
    targets.push({ type: 'space', id: space.id, name: space.name });
  }

  for (const library of libraries) {
    if (library.hasUploadPath) {
      targets.push({ type: 'library', id: library.id, name: library.name });
    }
  }

  return targets;
};
