import { BadRequestException, NotFoundException } from '@nestjs/common';
import { JobName } from 'src/enum.js';
import { PersonService } from 'src/services/person.service.js';
import { AssetFaceFactory } from 'test/factories/asset-face.factory.js';
import { AssetFactory } from 'test/factories/asset.factory.js';
import { AuthFactory } from 'test/factories/auth.factory.js';
import { PersonGroupFactory } from 'test/factories/person-group.factory.js';
import { PersonFactory } from 'test/factories/person.factory.js';
import { getForFaceSearch, getForFacialRecognitionJob } from 'test/mappers.js';
import { newUuid } from 'test/small.factory.js';
import { ServiceMocks, newTestService } from 'test/utils.js';

// fork: shared-libraries - space-scoped people (S9).
describe('PersonService space people', () => {
  let sut: PersonService;
  let mocks: ServiceMocks;

  beforeEach(() => {
    ({ sut, mocks } = newTestService(PersonService));
  });

  describe('getAll', () => {
    it('includes people of timeline-visible member spaces', async () => {
      const auth = AuthFactory.create();
      const spaceId = newUuid();
      const spacePerson = PersonFactory.create({ spaceId });

      mocks.person.getMemberSpaceIds.mockResolvedValue([{ spaceId, showInTimeline: true }]);
      mocks.person.getAllForUser.mockResolvedValue({ items: [spacePerson], hasNextPage: false });
      mocks.person.getNumberOfPeople.mockResolvedValue({ total: 1, hidden: 0 });

      await expect(sut.getAll(auth, { withHidden: false, page: 1, size: 10 })).resolves.toEqual({
        hasNextPage: false,
        total: 1,
        hidden: 0,
        people: [expect.objectContaining({ id: spacePerson.personGroupId, spaceId })],
      });
      expect(mocks.person.getMemberSpaceIds).toHaveBeenCalledWith(auth.user.id, true);
      expect(mocks.person.getAllForUser).toHaveBeenCalledWith({ skip: 0, take: 10 }, auth.user.id, {
        withHidden: false,
        memberSpaceIds: [spaceId],
      });
      expect(mocks.person.getNumberOfPeople).toHaveBeenCalledWith(auth.user.id, [spaceId]);
    });

    it('omits the space scope for non-members', async () => {
      const auth = AuthFactory.create();
      mocks.person.getMemberSpaceIds.mockResolvedValue([]);
      mocks.person.getAllForUser.mockResolvedValue({ items: [], hasNextPage: false });
      mocks.person.getNumberOfPeople.mockResolvedValue({ total: 0, hidden: 0 });

      await sut.getAll(auth, { withHidden: false, page: 1, size: 10 });

      expect(mocks.person.getAllForUser).toHaveBeenCalledWith({ skip: 0, take: 10 }, auth.user.id, {
        withHidden: false,
      });
    });
  });

  describe('getById', () => {
    it('resolves a member space person the viewer does not own', async () => {
      const auth = AuthFactory.create();
      const spacePerson = PersonFactory.create({ spaceId: newUuid() });

      mocks.access.person.checkOwnerAccess.mockResolvedValue(new Set([spacePerson.personGroupId]));
      mocks.person.getByGroupId.mockResolvedValue(undefined);
      mocks.person.getByGroupIdForUser.mockResolvedValue(spacePerson);

      await expect(sut.getById(auth, spacePerson.personGroupId)).resolves.toEqual(
        expect.objectContaining({ id: spacePerson.personGroupId, spaceId: spacePerson.spaceId }),
      );
    });

    it('rejects outsiders', async () => {
      const auth = AuthFactory.create();
      mocks.access.person.checkOwnerAccess.mockResolvedValue(new Set());

      await expect(sut.getById(auth, newUuid())).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('create', () => {
    it('creates a space-scoped person for members', async () => {
      const auth = AuthFactory.create();
      const spaceId = newUuid();
      const group = PersonGroupFactory.create();
      const spacePerson = PersonFactory.create({ personGroupId: group.id, spaceId });

      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set([spaceId]));
      mocks.person.createSpaceGroup.mockResolvedValue(group);
      mocks.person.create.mockResolvedValue(spacePerson);

      await expect(sut.create(auth, { name: 'Mom', spaceId })).resolves.toEqual(expect.objectContaining({ spaceId }));
      expect(mocks.person.createSpaceGroup).toHaveBeenCalledWith(spaceId);
      expect(mocks.person.create).toHaveBeenCalledWith(expect.objectContaining({ spaceId }));
    });

    it('rejects space creation for non-members', async () => {
      const auth = AuthFactory.create();
      mocks.access.space.checkMemberAccess.mockResolvedValue(new Set());

      await expect(sut.create(auth, { spaceId: newUuid() })).rejects.toBeInstanceOf(NotFoundException);
      expect(mocks.person.createSpaceGroup).not.toHaveBeenCalled();
    });
  });

  describe('mergePeople', () => {
    it('merges space people within their space', async () => {
      const auth = AuthFactory.create();
      const spaceId = newUuid();
      const target = PersonFactory.create({ name: '', spaceId });
      const source = PersonFactory.create({ name: 'Mom', spaceId });

      mocks.access.person.checkOwnerAccess.mockResolvedValue(new Set([target.personGroupId, source.personGroupId]));
      mocks.person.getForMergePerson.mockResolvedValue([target, source]);
      mocks.person.update.mockResolvedValue(target);
      mocks.person.delete.mockResolvedValue([]);

      const results = await sut.mergePeople(auth, { ids: [target.personGroupId, source.personGroupId] });

      expect(results).toEqual([{ id: source.personGroupId, success: true }]);
      expect(mocks.person.reassignFaces).toHaveBeenCalledWith({
        oldPersonGroupId: source.personGroupId,
        newPersonGroupId: target.personGroupId,
        spaceId,
      });
      expect(mocks.person.delete).toHaveBeenCalledWith([source.personGroupId], target.ownerId, spaceId);
    });
  });

  describe('handleRecognizeFaces', () => {
    it('clusters a space-asset face only against its space', async () => {
      const spaceId = newUuid();
      const asset = AssetFactory.create({ spaceId });
      const face = AssetFaceFactory.create({ assetId: asset.id });
      const group = PersonGroupFactory.create();

      mocks.systemMetadata.get.mockResolvedValue({ machineLearning: { facialRecognition: { minFaces: 1 } } });
      mocks.search.searchFaces.mockResolvedValue([getForFaceSearch(face, 0.1)]);
      mocks.person.getFaceForFacialRecognitionJob.mockResolvedValue(getForFacialRecognitionJob(face, asset));
      mocks.person.createSpaceGroup.mockResolvedValue(group);
      mocks.person.getSpacePerson.mockResolvedValue(undefined);
      mocks.person.create.mockResolvedValue(PersonFactory.create({ personGroupId: group.id, spaceId }));

      await sut.handleRecognizeFaces({ id: face.id });

      expect(mocks.search.searchFaces).toHaveBeenCalledWith(expect.objectContaining({ spaceId }));
      expect(mocks.search.searchFaces).not.toHaveBeenCalledWith(
        expect.objectContaining({ clusterGroupId: expect.anything() }),
      );
      expect(mocks.person.createGroup).not.toHaveBeenCalled();
      expect(mocks.person.createSpaceGroup).toHaveBeenCalledWith(spaceId);
      expect(mocks.person.getSpacePerson).toHaveBeenCalledWith(spaceId, group.id);
      expect(mocks.person.getByGroupId).not.toHaveBeenCalled();
      expect(mocks.person.create).toHaveBeenCalledWith(expect.objectContaining({ spaceId }));
    });
  });

  describe('handleContainerMove', () => {
    it('detaches faces from the source space and re-queues recognition', async () => {
      const ownerId = newUuid();
      const spaceId = newUuid();
      const asset = AssetFactory.create({ ownerId, spaceId });
      const faceId = newUuid();

      mocks.asset.getByIds.mockResolvedValue([asset]);
      mocks.person.detachFacesForMove.mockResolvedValue([faceId]);

      await sut.handleContainerMove({ assetIds: [asset.id], fromSpaceId: spaceId, toSpaceId: null });

      expect(mocks.person.detachFacesForMove).toHaveBeenCalledWith([asset.id], { spaceId, ownerId });
      expect(mocks.job.queueAll).toHaveBeenCalledWith([{ name: JobName.FacialRecognition, data: { id: faceId } }]);
    });

    it('does nothing when the container does not change', async () => {
      const spaceId = newUuid();

      await sut.handleContainerMove({ assetIds: [newUuid()], fromSpaceId: spaceId, toSpaceId: spaceId });

      expect(mocks.person.detachFacesForMove).not.toHaveBeenCalled();
      expect(mocks.job.queueAll).not.toHaveBeenCalled();
    });
  });
});
