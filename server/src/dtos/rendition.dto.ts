import { createZodDto } from 'nestjs-zod';
import z from 'zod';
import { UploadFieldName } from 'src/dtos/asset-media.dto.js';
import { ApiCustomExtension } from 'src/enum.js';

const AssetRenditionUploadSchema = z
  .object({
    /**
     * The properties below are added to correctly generate the API docs and client SDKs. Validation should be handled
     * in the controller. File parts never reach the request body, so they must be optional here
     */
    [UploadFieldName.ASSET_DATA]: z
      .any()
      .optional()
      .describe('Rendered asset file data (image or video)')
      .meta({ type: 'string', format: 'binary', [ApiCustomExtension.Required]: true }),
  })
  .meta({ id: 'AssetRenditionUploadDto' });

export class AssetRenditionUploadDto extends createZodDto(AssetRenditionUploadSchema) {}
