import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import type { AuthDto } from 'src/dtos/auth.dto.js';
import {
  SharedSpaceCreateDto,
  SharedSpaceMemberResponseDto,
  SharedSpaceMembersDto,
  SharedSpaceOwnerDto,
  SharedSpaceResponseDto,
  SharedSpaceTimelineDto,
  SharedSpaceUpdateDto,
} from 'src/dtos/shared-space.dto.js';
import { Permission, SharedSpaceRole } from 'src/enum.js';
import { AccessRepository } from 'src/repositories/access.repository.js';
import { SharedSpaceRepository, type SharedSpaceWithStats } from 'src/repositories/shared-space.repository.js';
import { AssetRelocationService } from 'src/services/asset-relocation.service.js';
import { requireAccess } from 'src/utils/access.js';

const mapSpace = (space: SharedSpaceWithStats): SharedSpaceResponseDto => ({
  id: space.id,
  name: space.name,
  description: space.description,
  role: space.role,
  memberCount: Number(space.memberCount),
  assetCount: Number(space.assetCount),
  showInTimeline: space.showInTimeline,
  thumbnailAssetId: space.thumbnailAssetId,
  createdAt: space.createdAt,
  updatedAt: space.updatedAt,
});

@Injectable()
export class SharedSpaceService {
  constructor(
    private accessRepository: AccessRepository,
    private sharedSpaceRepository: SharedSpaceRepository,
    private assetRelocationService: AssetRelocationService,
  ) {}

  private async require(auth: AuthDto, permission: Permission, id: string) {
    // fork: shared-libraries - space surfaces report denial as 403 (S4 contract);
    // upstream requireAccess uses 400 to hide existence, which stays on upstream endpoints.
    try {
      await requireAccess(this.accessRepository, { auth, permission, ids: [id] });
    } catch (error) {
      if (error instanceof BadRequestException) throw new ForbiddenException(error.message);
      throw error;
    }
  }

  private async storageLabel(name: string) {
    const base =
      name
        .normalize('NFKD')
        .replaceAll(/[\u{0300}-\u{036F}]/gu, '')
        .toLowerCase()
        .replaceAll(/[^a-z0-9]+/g, '-')
        .replaceAll(/^-|-$/g, '')
        .slice(0, 96) || 'space';
    const labels = new Set(await this.sharedSpaceRepository.getStorageLabelCandidates(base));
    if (!labels.has(base)) return base;
    for (let suffix = 2; ; suffix++) {
      const label = `${base}-${suffix}`;
      if (!labels.has(label)) return label;
    }
  }

  async create(auth: AuthDto, dto: SharedSpaceCreateDto): Promise<SharedSpaceResponseDto> {
    const space = await this.sharedSpaceRepository.create({
      name: dto.name,
      description: dto.description,
      createdById: auth.user.id,
      storageLabel: await this.storageLabel(dto.name),
    });
    return mapSpace({
      ...space,
      role: SharedSpaceRole.Owner,
      showInTimeline: true,
      memberCount: 1,
      assetCount: 0,
    });
  }

  async getAll(auth: AuthDto): Promise<SharedSpaceResponseDto[]> {
    const spaces = await this.sharedSpaceRepository.getAll(auth.user.id);
    return spaces.map((space) => mapSpace(space));
  }

  async get(auth: AuthDto, id: string): Promise<SharedSpaceResponseDto> {
    await this.require(auth, Permission.SharedSpaceRead, id);
    const space = await this.sharedSpaceRepository.get(id, auth.user.id);
    if (!space) throw new BadRequestException(`Shared space ${id} not found`);
    return mapSpace(space);
  }

  async update(auth: AuthDto, id: string, dto: SharedSpaceUpdateDto): Promise<SharedSpaceResponseDto> {
    await this.require(auth, Permission.SharedSpaceUpdate, id);
    if (dto.thumbnailAssetId) {
      await requireAccess(this.accessRepository, {
        auth,
        permission: Permission.AssetRead,
        ids: [dto.thumbnailAssetId],
      });
    }
    await this.sharedSpaceRepository.update(id, dto);
    return this.get(auth, id);
  }

  async delete(auth: AuthDto, id: string): Promise<void> {
    await this.require(auth, Permission.SharedSpaceDelete, id);
    let queueAfterCommit: (() => Promise<void>) | undefined;
    await this.sharedSpaceRepository.deleteSpace(id, async (assetIds, trx) => {
      queueAfterCommit = await this.assetRelocationService.requestRelocation(assetIds, auth.user.id, trx);
    });
    await queueAfterCommit?.();
  }

  async getMembers(auth: AuthDto, id: string): Promise<SharedSpaceMemberResponseDto[]> {
    await this.require(auth, Permission.SharedSpaceRead, id);
    return await this.sharedSpaceRepository.getMembers(id);
  }

  async addMembers(auth: AuthDto, id: string, dto: SharedSpaceMembersDto): Promise<void> {
    await this.require(auth, Permission.SharedSpaceMemberCreate, id);
    if (!(await this.sharedSpaceRepository.addMembers(id, dto.userIds))) {
      throw new BadRequestException('Users must exist and not already be members');
    }
  }

  async removeMember(auth: AuthDto, id: string, userId: string): Promise<void> {
    await this.require(auth, Permission.SharedSpaceMemberDelete, id);
    const members = await this.sharedSpaceRepository.getMembers(id);
    const member = members.find((member) => member.userId === userId);
    if (!member) throw new BadRequestException('User is not a member');
    if (member.role === SharedSpaceRole.Owner)
      throw new BadRequestException('The owner must transfer or delete the space');
    if (userId !== auth.user.id && members.every((member) => member.userId !== auth.user.id)) {
      throw new BadRequestException('Not a member');
    }
    await this.sharedSpaceRepository.removeMember(id, userId);
  }

  async transferOwner(auth: AuthDto, id: string, dto: SharedSpaceOwnerDto): Promise<void> {
    await this.require(auth, Permission.SharedSpaceDelete, id);
    if (!(await this.sharedSpaceRepository.isMember(id, dto.userId))) {
      throw new BadRequestException('New owner must be a contributor');
    }
    if (dto.userId === auth.user.id) return;
    await this.sharedSpaceRepository.transferOwner(id, auth.user.id, dto.userId);
  }

  async updateMyTimeline(auth: AuthDto, id: string, dto: SharedSpaceTimelineDto): Promise<void> {
    await this.require(auth, Permission.SharedSpaceMemberUpdate, id);
    await this.sharedSpaceRepository.updateMember(id, auth.user.id, dto);
  }
}
