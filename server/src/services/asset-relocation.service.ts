import { Injectable } from '@nestjs/common';
import { basename, extname, join } from 'node:path';
import type { ArgOf } from 'src/repositories/event.repository.js';
import type { DB } from 'src/schema/index.js';
import type { JobOf } from 'src/types.js';
import { StorageCore } from 'src/cores/storage.core.js';
import { OnEvent, OnJob } from 'src/decorators.js';
import {
  AssetFileType,
  AssetPathType,
  BootstrapEventPriority,
  ChecksumAlgorithm,
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
import { isPathInside } from 'src/utils/path.js';

type RelocationTransaction = import('kysely').Kysely<DB>;
type QueueAfterCommit = () => Promise<void>;

export { isPathInside } from 'src/utils/path.js';

export interface ContainerPathFinding {
  assetId: string;
  kind: 'original' | 'sidecar' | 'derived';
  actual: string;
  expected: string;
}

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

  @OnEvent({ name: 'AssetMetadataExtracted', server: true })
  async onAssetMetadataExtracted({ assetId, userId }: ArgOf<'AssetMetadataExtracted'>) {
    // fork: shared-libraries - uploads stay in staging until metadata/template work is complete.
    const asset = await this.assetRepository.getForRelocation(assetId);
    if (asset?.spaceId) await this.requestRelocation([assetId], userId);
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

  // fork: shared-libraries - user deletion must complete re-keying before upstream folder removal.
  async relocateInline(assetIds: string[]): Promise<void> {
    for (const id of assetIds) await this.relocate(id);
  }

  // fork: shared-libraries (S10) - report-only §7 audit ("Verify container paths").
  // Originals follow the same branches as relocate(): exact nested paths when the
  // storage template is off, container-root containment when it is on (date-prefix
  // rendering is upstream's business), and import-root containment for
  // external-library assets (scanned files stay where found). Sidecars must sit next
  // to the actual original (`<original>.xmp`, as the move worker writes them);
  // derived files are exact, via the same computation the move worker uses.
  async auditContainerPaths(): Promise<ContainerPathFinding[]> {
    const { storageTemplate } = await this.getConfig({ withCache: true });
    const findings: ContainerPathFinding[] = [];
    for (const id of await this.assetRepository.getAuditIds()) {
      const asset = await this.assetRepository.getForRelocation(id);
      if (!asset) {
        continue;
      }
      if (asset.libraryId) {
        const roots = [...(asset.importPaths ?? []), ...(asset.uploadPath ? [asset.uploadPath] : [])];
        if (roots.every((root) => !isPathInside(asset.originalPath, root))) {
          findings.push({
            assetId: asset.id,
            kind: 'original',
            actual: asset.originalPath,
            expected: asset.uploadPath ?? roots[0] ?? '(library import root)',
          });
        }
      } else if (storageTemplate.enabled) {
        const root = asset.spaceId
          ? StorageCore.getLibraryFolder({ id: `shared/${asset.spaceStorageLabel}`, storageLabel: null })
          : StorageCore.getLibraryFolder({ id: asset.ownerId, storageLabel: asset.ownerStorageLabel ?? null });
        if (!isPathInside(asset.originalPath, root)) {
          findings.push({ assetId: asset.id, kind: 'original', actual: asset.originalPath, expected: root });
        }
      } else {
        const target = StorageCore.getNestedPath(
          StorageFolder.Upload,
          StorageCore.getStorageKey(asset),
          basename(asset.originalPath),
        );
        if (target !== asset.originalPath) {
          findings.push({ assetId: asset.id, kind: 'original', actual: asset.originalPath, expected: target });
        }
      }
      const sidecar = getAssetFile(asset.files, AssetFileType.Sidecar, { isEdited: false });
      if (sidecar && sidecar.path !== `${asset.originalPath}.xmp`) {
        findings.push({
          assetId: asset.id,
          kind: 'sidecar',
          actual: sidecar.path,
          expected: `${asset.originalPath}.xmp`,
        });
      }
      for (const file of asset.files) {
        if (file.type === AssetFileType.Sidecar) {
          continue;
        }
        const target = this.getDerivedTarget(asset, file);
        if (target !== file.path) {
          findings.push({ assetId: asset.id, kind: 'derived', actual: file.path, expected: target });
        }
      }
    }
    return findings;
  }

  @OnJob({ name: JobName.ContainerPathsAudit, queue: QueueName.IntegrityCheck })
  async handleContainerPathsAudit(): Promise<JobStatus> {
    const findings = await this.auditContainerPaths();
    if (findings.length === 0) {
      this.logger.log('Container paths audit: every file is at its §7 path');
    } else {
      this.logger.warn(`Container paths audit: ${findings.length} misplaced file(s)`);
      for (const finding of findings.slice(0, 50)) {
        this.logger.warn(
          `Misplaced ${finding.kind} for asset ${finding.assetId}: ${finding.actual} (expected ${finding.expected})`,
        );
      }
    }
    return JobStatus.Success;
  }

  private async relocate(id: string, depth = 0): Promise<void> {
    const asset = await this.assetRepository.getForRelocation(id);
    if (!asset) return;

    const { storageTemplate } = await this.getConfig({ withCache: true });
    if (asset.libraryId) {
      await this.moveExternalOriginal(asset);
    } else {
      // fork: shared-libraries (R10-02) - an asset that left its library still lives
      // under an import root. Adopt a content checksum first: scan-created assets carry
      // a path-derived checksum (sha1-path) that cross-device verification would reject.
      if ((asset.importPaths ?? []).some((importPath) => isPathInside(asset.originalPath, importPath))) {
        await this.adoptContentChecksum(asset);
      }
      if (storageTemplate.enabled) {
        await StorageTemplateService.getInstance().moveAssetToTemplatePath(asset.id);
      } else {
        await this.moveUntemplatedOriginal(asset);
      }
    }

    // fork: shared-libraries (R17-01) - one bad derived file must not strand the rest;
    // the first failure is rethrown below so the relocation row stays pending.
    let derivedError: unknown;
    for (const file of asset.files) {
      if (file.type === AssetFileType.Sidecar) continue;
      const target = this.getDerivedTarget(asset, file);
      if (target !== file.path) {
        try {
          await this.storageCore.moveFile({
            entityId: asset.id,
            pathType: file.type,
            oldPath: file.path,
            newPath: target,
          });
        } catch (error) {
          this.logger.warn(
            `Unable to relocate derived file for asset ${asset.id}: ${file.path} => ${target}: ${error}`,
          );
          derivedError ??= error;
        }
      }
    }
    if (derivedError) {
      throw derivedError;
    }

    if (depth === 0 && asset.livePhotoVideoId) await this.relocate(asset.livePhotoVideoId, 1);
  }

  // fork: shared-libraries (R10-02) - promote a scan-created (sha1-path) asset to a
  // content checksum as its bytes leave the library for managed storage.
  private async adoptContentChecksum(
    asset: NonNullable<Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>>,
  ): Promise<void> {
    if (asset.checksumAlgorithm !== ChecksumAlgorithm.sha1Path) {
      return;
    }
    const checksum = await this.cryptoRepository.hashFile(asset.originalPath);
    await this.assetRepository.update({ id: asset.id, checksum, checksumAlgorithm: ChecksumAlgorithm.sha1File });
    asset.checksum = checksum;
  }

  private async moveUntemplatedOriginal(asset: Awaited<ReturnType<typeof this.assetRepository.getForRelocation>>) {
    if (!asset) return;
    const target = StorageCore.getNestedPath(
      StorageFolder.Upload,
      StorageCore.getStorageKey(asset),
      basename(asset.originalPath),
    );
    if (target !== asset.originalPath) {
      await this.moveOriginalAndSidecar(asset, target);
      return;
    }
    // fork: shared-libraries (R17-01) - the original is already placed (a personal upload
    // with the template off); still co-locate a staging sidecar next to it (§7 invariant).
    const sidecar = getAssetFile(asset.files, AssetFileType.Sidecar, { isEdited: false });
    const sidecarTarget = `${asset.originalPath}.xmp`;
    if (sidecar && sidecar.path !== sidecarTarget) {
      await this.storageCore.moveFile({
        entityId: asset.id,
        pathType: AssetFileType.Sidecar,
        oldPath: sidecar.path,
        newPath: sidecarTarget,
      });
    }
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
