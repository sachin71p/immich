import { ForbiddenException, Injectable } from '@nestjs/common';
import type { Expression, ExpressionBuilder, SqlBool } from 'kysely';
import { AuthDto } from 'src/dtos/auth.dto.js';
import { LibraryRepository } from 'src/repositories/library.repository.js';
import { PartnerRepository } from 'src/repositories/partner.repository.js';
import { SharedSpaceRepository } from 'src/repositories/shared-space.repository.js';
import { UserRepository } from 'src/repositories/user.repository.js';
import { DB } from 'src/schema/index.js';
import { getMyPartnerIds } from 'src/utils/asset.util.js';
import { getPreferences } from 'src/utils/preferences.js';

export interface ContainerScope {
  personalUserIds: string[];
  spaceIds: string[];
  libraryIds: string[];
}

export type ContainerScopePurpose = 'timeline' | 'manage' | 'locked';

export interface ContainerScopeFilter {
  spaceId?: string;
  libraryId?: string;
  personalOnly?: boolean;
}

/**
 * Restricts the unaliased asset table to the containers visible to a user.
 * Empty branches are deliberately false, so an empty membership never produces
 * an invalid `ANY('{}')` predicate or broadens a query.
 */
export const withContainerScope = (eb: ExpressionBuilder<DB, 'asset'>, scope: ContainerScope): Expression<SqlBool> => {
  const branches: Expression<SqlBool>[] = [];

  if (scope.personalUserIds.length > 0) {
    branches.push(
      eb.and([
        eb('asset.spaceId', 'is', null),
        eb('asset.libraryId', 'is', null),
        eb('asset.ownerId', 'in', scope.personalUserIds),
      ]),
    );
  }
  if (scope.spaceIds.length > 0) {
    branches.push(eb('asset.spaceId', 'in', scope.spaceIds));
  }
  if (scope.libraryIds.length > 0) {
    branches.push(eb('asset.libraryId', 'in', scope.libraryIds));
  }

  return branches.length === 0 ? eb.lit(false) : eb.or(branches);
};

@Injectable()
export class ContainerScopeService {
  constructor(
    private userRepository: UserRepository,
    private partnerRepository: PartnerRepository,
    private sharedSpaceRepository: SharedSpaceRepository,
    private libraryRepository: LibraryRepository,
  ) {}

  async resolve(
    auth: AuthDto,
    {
      purpose,
      withPartners = false,
      filter = {},
    }: { purpose: ContainerScopePurpose; withPartners?: boolean; filter?: ContainerScopeFilter },
  ): Promise<ContainerScope> {
    const filters = [filter.spaceId, filter.libraryId, filter.personalOnly].filter((value) => value !== undefined);
    if (filters.length > 1) {
      // DTO validation is the public 400; this prevents an unsafe scope for internal callers.
      throw new ForbiddenException('Only one container filter may be specified');
    }

    if (filter.personalOnly) {
      return { personalUserIds: [auth.user.id], spaceIds: [], libraryIds: [] };
    }
    if (filter.spaceId) {
      if (!(await this.sharedSpaceRepository.isMember(filter.spaceId, auth.user.id))) {
        throw new ForbiddenException('You do not have access to this shared space');
      }
      return { personalUserIds: [], spaceIds: [filter.spaceId], libraryIds: [] };
    }
    if (filter.libraryId) {
      const libraries = await this.libraryRepository.getShared(auth.user.id);
      if (!libraries.some((library) => library.id === filter.libraryId)) {
        throw new ForbiddenException('You do not have access to this library');
      }
      return { personalUserIds: [], spaceIds: [], libraryIds: [filter.libraryId] };
    }

    if (purpose === 'locked') {
      return { personalUserIds: [auth.user.id], spaceIds: [], libraryIds: [] };
    }

    const [spaces, libraries, metadata] = await Promise.all([
      this.sharedSpaceRepository.getAll(auth.user.id),
      this.libraryRepository.getShared(auth.user.id),
      this.userRepository.getMetadata(auth.user.id),
    ]);

    if (purpose === 'manage') {
      return {
        personalUserIds: [auth.user.id],
        spaceIds: spaces.map(({ id }) => id),
        libraryIds: libraries.map(({ id }) => id),
      };
    }

    const preferences = getPreferences(metadata).sharedLibraries;
    const personalUserIds = preferences.showPersonalInTimeline ? [auth.user.id] : [];
    if (withPartners) {
      personalUserIds.push(
        ...(await getMyPartnerIds({ userId: auth.user.id, repository: this.partnerRepository, timelineEnabled: true })),
      );
    }
    return {
      personalUserIds,
      spaceIds: spaces.filter(({ showInTimeline }) => showInTimeline).map(({ id }) => id),
      libraryIds: libraries
        .filter(({ id, ownerId, showInTimeline }) =>
          ownerId !== auth.user.id ? (showInTimeline ?? true) : !preferences.hiddenOwnedLibraryIds.includes(id),
        )
        .map(({ id }) => id),
    };
  }
}
