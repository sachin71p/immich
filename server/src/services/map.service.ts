import { Inject, Injectable } from '@nestjs/common';
import { AuthDto } from 'src/dtos/auth.dto.js';
import { MapMarkerDto, MapMarkerResponseDto, MapReverseGeocodeDto } from 'src/dtos/map.dto.js';
import { BaseService } from 'src/services/base.service.js';
import { getMyPartnerIds } from 'src/utils/asset.util.js';
import { ContainerScopeService } from 'src/utils/container-scope.js';

@Injectable()
export class MapService extends BaseService {
  // fork: shared-libraries
  @Inject() private containerScopeService!: ContainerScopeService;
  async getMapMarkers(auth: AuthDto, options: MapMarkerDto): Promise<MapMarkerResponseDto[]> {
    const userIds = [auth.user.id];
    if (options.withPartners) {
      const partnerIds = await getMyPartnerIds({ userId: auth.user.id, repository: this.partnerRepository });
      userIds.push(...partnerIds);
    }

    const albumIds = options.withSharedAlbums ? await this.albumRepository.getAllIds(auth.user.id) : [];

    const scope = await this.containerScopeService.resolve(auth, {
      purpose: 'timeline',
      withPartners: options.withPartners,
      filter: { spaceId: options.spaceId, libraryId: options.libraryId, personalOnly: options.personalOnly },
    });
    return scope
      ? this.mapRepository.getMapMarkers(auth.user.id, userIds, albumIds, options, scope)
      : this.mapRepository.getMapMarkers(auth.user.id, userIds, albumIds, options);
  }

  async reverseGeocode(dto: MapReverseGeocodeDto) {
    const { lat: latitude, lon: longitude } = dto;
    // eventually this should probably return an array of results
    const result = await this.mapRepository.reverseGeocode({ latitude, longitude });
    return result ? [result] : [];
  }
}
