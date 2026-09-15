import { BadRequestException, Inject, Injectable } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto.js';
import { TimeBucketAssetDto, TimeBucketDto, TimeBucketsResponseDto } from 'src/dtos/time-bucket.dto.js';
import { AssetVisibility, Permission } from 'src/enum.js';
import { TimeBucketOptions } from 'src/repositories/asset.repository.js';
import { BaseService } from 'src/services/base.service.js';
import { requireElevatedPermission } from 'src/utils/access.js';
import { getMyPartnerIds } from 'src/utils/asset.util.js';
import { ContainerScopeService } from 'src/utils/container-scope.js';

@Injectable()
export class TimelineService extends BaseService {
  // fork: shared-libraries
  @Inject() private containerScopeService!: ContainerScopeService;
  async getTimeBuckets(auth: AuthDto, dto: TimeBucketDto): Promise<TimeBucketsResponseDto[]> {
    await this.timeBucketChecks(auth, dto);
    const timeBucketOptions = await this.buildTimeBucketOptions(auth, dto);
    return await this.assetRepository.getTimeBuckets(timeBucketOptions, auth);
  }

  // pre-jsonified response
  async getTimeBucket(auth: AuthDto, dto: TimeBucketAssetDto): Promise<string> {
    await this.timeBucketChecks(auth, dto);
    const timeBucketOptions = await this.buildTimeBucketOptions(auth, { ...dto });

    // TODO: use id cursor for pagination
    const bucket = await this.assetRepository.getTimeBucket(dto.timeBucket, timeBucketOptions, auth);
    return bucket.assets;
  }

  private async buildTimeBucketOptions(auth: AuthDto, dto: TimeBucketDto): Promise<TimeBucketOptions> {
    const { userId, ...options } = dto;
    let userIds: string[] | undefined = [auth.user.id];

    if (userId) {
      userIds = [userId];
      // Explicit partner timelines retain upstream behavior and deliberately ignore preferences.
      if (dto.withPartners) {
        userIds.push(
          ...(await getMyPartnerIds({
            userId: auth.user.id,
            repository: this.partnerRepository,
            timelineEnabled: true,
          })),
        );
      }
    }

    if (dto.albumId) {
      return { ...options, userIds: undefined };
    }

    const scope = userId
      ? undefined
      : await this.containerScopeService.resolve(auth, {
          purpose:
            dto.visibility === AssetVisibility.Locked
              ? 'locked'
              : dto.visibility === AssetVisibility.Archive
                ? 'manage'
                : 'timeline',
          withPartners: dto.withPartners,
          filter: { spaceId: dto.spaceId, libraryId: dto.libraryId, personalOnly: dto.personalOnly },
        });
    return { ...options, userIds, ...(scope && { scope }) };
  }

  private async timeBucketChecks(auth: AuthDto, dto: TimeBucketDto) {
    if (dto.visibility === AssetVisibility.Locked) {
      requireElevatedPermission(auth);
    }

    // fork: shared-libraries - upstream defaulted dto.userId to the session user here, which ran the
    // TimelineRead gate below for own-timeline reads. The default moved to buildTimeBucketOptions (so
    // scope resolution still applies), but the gate must stay: otherwise shared-link sessions skip it.
    if (!dto.albumId && !dto.userId) {
      await this.requireAccess({ auth, permission: Permission.TimelineRead, ids: [auth.user.id] });
    }

    if (dto.albumId) {
      await this.requireAccess({ auth, permission: Permission.AlbumRead, ids: [dto.albumId] });
    }

    if (dto.userId) {
      await this.requireAccess({ auth, permission: Permission.TimelineRead, ids: [dto.userId] });
      if (dto.visibility === AssetVisibility.Archive) {
        await this.requireAccess({ auth, permission: Permission.ArchiveRead, ids: [dto.userId] });
      }
      if (dto.visibility === AssetVisibility.Locked && dto.userId !== auth.user.id) {
        throw new BadRequestException("You may not access another user's locked timeline");
      }
    }

    if (dto.tagId) {
      await this.requireAccess({ auth, permission: Permission.TagRead, ids: [dto.tagId] });
    }

    if (auth.sharedLink && !auth.sharedLink.showExif) {
      dto.withCoordinates = false;
    }

    if (dto.withPartners) {
      const isRequestedLocked = dto.visibility === AssetVisibility.Locked;
      const isRequestedArchived = dto.visibility === AssetVisibility.Archive || dto.visibility === undefined;
      const isRequestedFavorite = dto.isFavorite === true || dto.isFavorite === false;
      const isRequestedTrash = dto.isTrashed === true;

      if (isRequestedLocked || isRequestedArchived || isRequestedFavorite || isRequestedTrash) {
        throw new BadRequestException(
          'withPartners is only supported for non-archived, non-trashed, non-favorited, non-locked assets',
        );
      }
    }
  }
}
