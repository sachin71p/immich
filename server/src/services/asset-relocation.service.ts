import { Injectable } from '@nestjs/common';
import { basename, extname, isAbsolute, join, relative, resolve } from 'node:path';
import type { DB } from 'src/schema/index.js';
import type { JobOf } from 'src/types.js';
import { StorageCore } from 'src/cores/storage.core.js';
import { OnEvent, OnJob } from 'src/decorators.js';
import {
  AssetFileType,
  AssetPathType,
  BootstrapEventPriority,
  ImageFormat,
  ImmichWorker,
  JobName,
  JobStatus,
  QueueName,
  StorageFolder,
} from 'src/enum.js';
import { BaseService } from 'src/services/base.service.js';
import { StorageTemplateService } from 'src/services/storage-template.service.js';
import { getAssetFile } from 'src/utils/asset.util.js';

type RelocationTransaction = import('kysely').Kysely<DB>;
type QueueAfterCommit = () => Promise<void>;

/** True only when candidate is inside root on a directory boundary. */
export const isPathInside = (candidate: string, root: string) => {
  const path = relative(resolve(root), resolve(candidate));
  return path !== '' && !path.startsWith('..') && !isAbsolute(path);
};

@Injectable()
export class AssetRelocationService extends BaseService {
  @OnEvent({
    name: 'AppBootstrap',
    priority: BootstrapEventPriority.SystemConfig,
    workers: [ImmichWorker.Microservices],
  })
  async onBootstrap() {
    // fork: shared-libraries - resume relocations left by a process crash after migrations are available.
    await this.jobRepository.queue({ name: JobName.AssetRelocateQueueAll });
  }

  // fork: shared-libraries - callers execute the returned callback only after their transaction commits.
  async requestRelocation(
    assetIds: string[],
    requestedById: string,
    trx?: RelocationTransaction,
  ): Promise<QueueAfterCommit | undefined> {
    await this.assetRepository.createRelocations(assetIds, requestedById, trx);
    const queueAfterCommit = () =>
      this.jobRepository.queueAll(assetIds.map((id) => ({ name: JobName.AssetRelocate, data: { id } })));
    if (trx) return queueAfterCommit;
    await queueAfterCommit();
  }

  @OnJob({ name: JobName.AssetRelocateQueueAll, queue: QueueName.StorageTemplateMigration })
  async handleQueueAll(): Promise<JobStatus> {
    const ids = await this.assetRepository.getPendingRelocationIds();
    await this.jobRepository.queueAll(ids.map((id) => ({ name: JobName.AssetRelocate, data: { id } })));
    return JobStatus.Success;
  }

  @OnJob({ name: JobName.AssetRelocate, queue: QueueName.StorageTemplateMigration })
  async handleRelocate({ id }: JobOf<JobName.AssetRelocate>): Promise<JobStatus> {
    try {
      await this.relocate(id);
      await this.assetRepository.completeRelocation(id);
      return JobStatus.Success;
    } catch (error: any) {
      await this.assetRepository.failRelocation(id, error?.message || String(error));
      throw error;
    }
  }

  private async relocate(id: string, depth = 0): Promise<void> {
    const asset = await this.assetRepository.getForRelocation(id);
    if (!asset) return;

    const { storageTemplate } = await this.getConfig({ withCache: true });
    if (asset.libraryId) {
      await this.moveExternalOriginal(asset);
    } else if (storageTemplate.enabled) {
      await StorageTemplateService.getInstance().moveAssetToTemplatePath(asset.id);
    } else {
      await this.moveUntemplatedOriginal(asset);
    }

    for (const file of asset.files) {
      if (file.type === AssetFileType.Sidecar) continue;
      const target = this.getDerivedTarget(asset, file);
      if (target !== file.path) {
        await this.storageCore.moveFile({
          entityId: asset.id,
          pathType: file.type,
          oldPath: file.path,
          newPath: target,
        });
      }
    }

    if (depth === 0 && asset.livePhotoVideoId) await this.relocate(asset.livePhotoVideoId, 1);
  }

  private async moveUntemplatedOriginal(asset: Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>) {
    if (!asset) return;
    const target = StorageCore.getNestedPath(
      StorageFolder.Upload,
      StorageCore.getStorageKey(asset),
      basename(asset.originalPath),
    );
    if (target === asset.originalPath) return;
    await this.moveOriginalAndSidecar(asset, target);
  }

  private async moveExternalOriginal(
    asset: NonNullable<Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>>,
  ) {
    if (
      !asset.uploadPath ||
      (asset.importPaths ?? []).some((importPath) => isPathInside(asset.originalPath, importPath))
    ) {
      return;
    }
    const extension = extname(asset.originalFileName || asset.originalPath);
    const stem = basename(asset.originalFileName || asset.originalPath, extension);
    let target = join(asset.uploadPath, `${stem}${extension}`);
    for (let suffix = 2; await this.storageRepository.checkFileExists(target); suffix++) {
      target = join(asset.uploadPath, `${stem}-${suffix}${extension}`);
    }
    await this.moveOriginalAndSidecar(asset, target);
  }

  private async moveOriginalAndSidecar(
    asset: NonNullable<Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>>,
    target: string,
  ) {
    if (!asset.fileSizeInByte) throw new Error(`Asset ${asset.id} is missing file size`);
    await this.storageCore.moveFile({
      entityId: asset.id,
      pathType: AssetPathType.Original,
      oldPath: asset.originalPath,
      newPath: target,
      assetInfo: { sizeInBytes: asset.fileSizeInByte, checksum: asset.checksum },
    });
    const sidecar = getAssetFile(asset.files, AssetFileType.Sidecar, { isEdited: false });
    if (sidecar) {
      await this.storageCore.moveFile({
        entityId: asset.id,
        pathType: AssetFileType.Sidecar,
        oldPath: sidecar.path,
        newPath: `${target}.xmp`,
      });
    }
  }

  private getDerivedTarget(
    asset: NonNullable<Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>>,
    file: { type: AssetFileType; path: string; isEdited: boolean },
  ) {
    if (file.type === AssetFileType.EncodedVideo) return StorageCore.getEncodedVideoPath(asset);
    return StorageCore.getImagePath(asset, {
      fileType: file.type,
      format: extname(file.path).slice(1) as ImageFormat,
      isEdited: file.isEdited,
    });
  }
}
