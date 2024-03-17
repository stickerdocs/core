import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/db/file_document.dart';
import 'package:stickerdocs_core/src/models/db/shared_sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker_file_document.dart';
import 'package:stickerdocs_core/src/models/event.dart';
import 'package:stickerdocs_core/src/models/event_file.dart';
import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/services/sync.dart';
import 'package:stickerdocs_core/src/services/sync_shared.dart';
import 'mock.mocks.dart';
import 'test_data.dart' as data;

class FakeSyncService extends Fake implements SyncService {
  List<Event>? capturedOutgoingEvents;

  @override
  Future<EventFile?> createAndUploadEventFile(List<Event> events,
      {String? userId}) async {
    capturedOutgoingEvents = events;
    return data.eventFile;
  }

  @override
  Future<List<Event>> acquireAndLoadEventFile(EventFile eventFile) async {
    return data.initialStickerShareEventsFromAlice();
  }
}

class FakeAPI extends Fake implements APIService {
  String? capturedUserId;
  EventFile? capturedEventFile;
  EventFile? fileToReturn;

  @override
  Future<List<EventFile>?> syncShared(String userId,
      [EventFile? eventFile]) async {
    capturedUserId = userId;
    capturedEventFile = eventFile;

    if (fileToReturn != null) {
      return [fileToReturn!];
    }

    return <EventFile>[];
  }

  @override
  Future<bool> syncSuccess(EventFile eventFile) async {
    return true;
  }
}

void main() {
  late SyncSharedService service;
  late DBService mockDB;
  late SyncService mockSyncService;
  late FakeSyncService fakeSyncService;
  late APIService mockAPI;
  late FakeAPI fakeAPI;
  late FileService mockFileService;

  setUp(() {
    GetIt.I.registerSingleton<ConfigService>(MockConfigService());
    GetIt.I.registerSingleton<DBService>(MockDBService());
    GetIt.I.registerSingleton<APIService>(FakeAPI());
    GetIt.I.registerSingleton<FileService>(MockFileService());
    GetIt.I.registerSingleton<AppLogic>(MockAppLogic());
    GetIt.I.registerSingleton<SyncSharedService>(SyncSharedService());
    GetIt.I.registerSingleton<SyncService>(FakeSyncService());

    service = GetIt.I.get<SyncSharedService>();
    mockDB = GetIt.I.get<DBService>();
    mockSyncService = GetIt.I.get<SyncService>();
    fakeSyncService = mockSyncService as FakeSyncService;
    mockAPI = GetIt.I.get<APIService>();
    fakeAPI = mockAPI as FakeAPI;
    mockFileService = GetIt.I.get<FileService>();
  });

  tearDown(() {
    GetIt.I.reset();
  });

  test('There are no shared stickers', () async {
    when(mockDB.getSharedStickers()).thenAnswer((_) async => []);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceInitialStickerShareOutgoingEvents);

    expect(incomingEvents, isEmpty);

    verify(mockDB.getSharedStickers()).called(1);
    verifyNoMoreInteractions(mockDB);
  });

  test('Alice has shared an unused sticker.', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.getStickerSnapshotEvents(data.aliceSticker.id))
        .thenAnswer((_) async => data.stickerSnapshotEvents);

    when(mockDB.getFileDocumentsLabelledWithStickerId(data.aliceSticker.id))
        .thenAnswer((_) async => []);

    when(mockDB.getStickerBlockDocumentsLabelledWithStickerIds(
        [data.aliceSticker.id])).thenAnswer((_) async => []);

    when(mockDB.isSharedObject(SharedSticker.tableName,
            data.stickerSharedByAliceToBob.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceInitialStickerShareOutgoingEvents);

    expect(incomingEvents, isEmpty);

    // Just the sticker
    final expectedEvents = data.stickerSnapshotEvents;
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));
  });

  test(
      'Alice shares a sticker with Bob. A single file is labelled with the sticker.',
      () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.getStickerSnapshotEvents(data.aliceSticker.id))
        .thenAnswer((_) async => data.stickerSnapshotEvents);

    when(mockDB.getFileSnapshotEvents(data.file.id))
        .thenAnswer((_) async => data.fileSnapshotEvents);

    when(mockDB.getFileDocumentsLabelledWithStickerId(data.aliceSticker.id))
        .thenAnswer((_) async => [data.fileDocument]);

    when(mockDB.getFileDocumentSnapshotEvents(data.fileDocument.id))
        .thenAnswer((_) async => data.fileDocumentSnapshotEvents);

    when(mockDB
            .getStickerFileDocumentSnapshotEvents(data.stickerFileDocument.id))
        .thenAnswer((_) async => data.stickerFileDocumentSnapshotEvents);

    when(mockDB.getStickerFileDocumentFromIds(
            data.stickerFileDocument.stickerId,
            data.stickerFileDocument.fileDocumentId))
        .thenAnswer((_) async => data.stickerFileDocument);

    when(mockDB.isSharedObject(SharedSticker.tableName,
            data.stickerSharedByAliceToBob.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.stickerFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(FileDocument.tableName, data.fileDocument.id,
            data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            File.tableName, data.file.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceInitialStickerShareOutgoingEvents);

    expect(incomingEvents, isEmpty);

    expect(fakeAPI.capturedUserId, data.bobUserId);
    expect(fakeAPI.capturedEventFile, data.eventFile);

    final expectedEvents = data.initialStickerShareEventsFromAlice();
    expect(fakeSyncService.capturedOutgoingEvents, expectedEvents);
  });

  setupBobReceivesSharedEventFromAlice({required List<String> filesIHave}) {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.bobsCopyOfAlicesSharedSticker]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.bobTrustsAlice]);

    when(mockDB.getAllFileIds()).thenAnswer((_) async => filesIHave);

    when(mockDB.isSharedObject(SharedSticker.tableName,
            data.stickerSharedByAliceToBob.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.stickerFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(FileDocument.tableName, data.fileDocument.id,
            data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            File.tableName, data.file.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.bobTrustsAlice.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            File.tableName, data.file.id, data.bobTrustsAlice.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.stickerFileDocument.id, data.bobTrustsAlice.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(FileDocument.tableName, data.fileDocument.id,
            data.bobTrustsAlice.id))
        .thenAnswer((_) async => false);

    when(mockDB.getTrustedUserByUserId(data.aliceUserId))
        .thenAnswer((realInvocation) async => data.bobTrustsAlice);

    fakeAPI.fileToReturn = data.eventFile;
  }

  verifyNoUnnecessaryCalls() {
    verify(mockDB.getSharedStickers()).called(1);
    verify(mockDB.getTrustedUsers()).called(1);
    verify(mockDB.getAllFileIds()).called(1);
  }

  test('Bob receives a shared sticker from Alice. Bob already has the file',
      () async {
    setupBobReceivesSharedEventFromAlice(filesIHave: [data.file.id]);

    final incomingEvents = await service.getSharedIncomingEvents([]);

    expect(incomingEvents, isNotEmpty);

    final expectedEvents = data.initialStickerShareEventsFromAlice();

    expect(jsonEncode(incomingEvents), jsonEncode(expectedEvents));

    // This should do nothing
    await service.uploadSharedFilesNotInMyAccount();

    verifyNoUnnecessaryCalls();
  });

  test(
      'Bob receives a shared sticker from Alice. Bob does not have the shared file',
      () async {
    setupBobReceivesSharedEventFromAlice(filesIHave: []);

    final incomingEvents = await service.getSharedIncomingEvents([]);

    expect(incomingEvents, isNotEmpty);

    final expectedEvents = data.initialStickerShareEventsFromAlice();

    // Each file should be tagged with source_user_id
    final sourceEventTimestamp = data.fileSnapshotEvents.first.timestamp;
    expectedEvents.add(Event(sourceEventTimestamp, 1, File.tableName,
        data.file.id, 'source_user_id', data.aliceUserId));

    expect(jsonEncode(incomingEvents), jsonEncode(expectedEvents));

    verifyNoUnnecessaryCalls();
  });

  test(
      'Bob receives a shared sticker from Alice. Bob does not have the shared file. We invoke the download mechanism',
      () async {
    setupBobReceivesSharedEventFromAlice(filesIHave: []);

    final incomingEvents = await service.getSharedIncomingEvents([]);

    expect(incomingEvents, isNotEmpty);

    when(mockDB.getFileById(data.file.id)).thenAnswer((_) async => data.file);

    when(mockFileService.downloadFile(data.file)).thenAnswer((_) async => true);
    when(mockFileService.uploadFile(data.file)).thenAnswer((_) async => true);

    await service.uploadSharedFilesNotInMyAccount();

    verify(mockFileService.downloadFile(data.file)).called(1);
    verify(mockFileService.uploadFile(data.file)).called(1);

    verify(mockDB.getFileById(data.file.id)).called(1);

    verifyNoUnnecessaryCalls();
  });

  test(
      'Bob receives a shared sticker from Alice. Notify the server of successful shared sync',
      () async {
    setupBobReceivesSharedEventFromAlice(filesIHave: [data.file.id]);

    final incomingEvents = await service.getSharedIncomingEvents([]);

    expect(incomingEvents, isNotEmpty);

    final expectedEvents = data.initialStickerShareEventsFromAlice();

    expect(jsonEncode(incomingEvents), jsonEncode(expectedEvents));

    // This should do nothing
    await service.markIncomingEventsSuccessfullySynchronised();

    verifyNoUnnecessaryCalls();
  });

  test('Alice shares another file with Bob.', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.getFileSnapshotEvents(data.file.id))
        .thenAnswer((_) async => data.fileSnapshotEvents);

    when(mockDB.getFileDocumentsLabelledWithStickerId(data.aliceSticker.id))
        .thenAnswer((_) async => [data.fileDocument]);

    when(mockDB.getFileDocumentSnapshotEvents(data.fileDocument.id))
        .thenAnswer((_) async => data.fileDocumentSnapshotEvents);

    when(mockDB
            .getStickerFileDocumentSnapshotEvents(data.stickerFileDocument.id))
        .thenAnswer((_) async => data.stickerFileDocumentSnapshotEvents);

    when(mockDB.getStickerFileDocumentFromIds(
            data.stickerFileDocument.stickerId,
            data.stickerFileDocument.fileDocumentId))
        .thenAnswer((_) async => data.stickerFileDocument);

    when(mockDB.isSharedObject(SharedSticker.tableName,
            data.stickerSharedByAliceToBob.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => true);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.stickerFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(FileDocument.tableName, data.fileDocument.id,
            data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            File.tableName, data.file.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    final incomingEvents = await service.getSharedIncomingEvents(
        data.aliceLabelsAnExistingFileWithASharedStickerEvents());

    expect(incomingEvents, isEmpty);

    final expectedEvents = data.sharedEventsFromAliceAfterSharingFile();
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));
  });

  test('Alice deletes a shared file', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.isSharedObject(
            File.tableName, data.file.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => true);

    final incomingEvents =
        await service.getSharedIncomingEvents(data.aliceDeletesAFileEvents());

    expect(incomingEvents, isEmpty);

    final expectedEvents = data.deleteFileEvents;
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));

    expect(fakeAPI.capturedEventFile!.fileIdsToUnshare, [data.file.id]);
  });

  test('Alice deletes a shared file document', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.isSharedObject(FileDocument.tableName, data.fileDocument.id,
            data.aliceTrustsBob.id))
        .thenAnswer((_) async => true);

    when(mockDB.getFileDocumentById(data.fileDocument.id))
        .thenAnswer((_) async => data.fileDocument);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceDeletesAFileDocumentEvents());

    expect(incomingEvents, isEmpty);

    final expectedEvents = data.deleteFileDocumentEvents;
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));

    expect(fakeAPI.capturedEventFile!.fileIdsToUnshare, [data.file.id]);
  });

  test('Alice deletes a shared sticker file document', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.stickerFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => true);

    when(mockDB.getStickerFileDocumentById(data.stickerFileDocument.id))
        .thenAnswer((_) async => data.stickerFileDocument);

    when(mockDB.getFileDocumentById(data.fileDocument.id))
        .thenAnswer((_) async => data.fileDocument);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceDeletesAStickerFileDocumentEvents());

    expect(incomingEvents, isEmpty);

    final expectedEvents = data.deleteStickerFileDocumentEvents;
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));

    expect(fakeAPI.capturedEventFile!.fileIdsToUnshare, [data.file.id]);
  });

  test('Alice deletes a shared sticker', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.aliceSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => true);

    when(mockDB.getSharedFilesLabelledWithStickerId(
            data.aliceSticker.id, data.aliceTrustsBob))
        .thenAnswer((_) async => [data.file]);

    final incomingEvents = await service
        .getSharedIncomingEvents(data.aliceDeletesAStickerEvents());

    expect(incomingEvents, isEmpty);

    final expectedEvents = data.deleteStickerEvents;
    expect(jsonEncode(fakeSyncService.capturedOutgoingEvents),
        jsonEncode(expectedEvents));

    expect(fakeAPI.capturedEventFile!.fileIdsToUnshare, [data.file.id]);
  });

  test('Alice labels a private file with a private shared sticker', () async {
    when(mockDB.getSharedStickers())
        .thenAnswer((_) async => [data.stickerSharedByAliceToBob]);

    when(mockDB.getTrustedUsers())
        .thenAnswer((_) async => [data.aliceTrustsBob]);

    when(mockDB.isSharedObject(
            Sticker.tableName, data.privateSticker.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(
            File.tableName, data.privateFile.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(FileDocument.tableName,
            data.privateFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.isSharedObject(StickerFileDocument.tableName,
            data.privateStickerFileDocument.id, data.aliceTrustsBob.id))
        .thenAnswer((_) async => false);

    when(mockDB.getStickerFileDocumentFromIds(
            data.privateSticker.id, data.privateFileDocument.id))
        .thenAnswer((_) async => data.stickerFileDocument);

    when(mockDB.getFileDocumentSnapshotEvents(data.privateFileDocument.id))
        .thenAnswer((_) async => data.privateFileDocumentSnapshotEvents);

    final incomingEvents = await service.getSharedIncomingEvents(
        data.aliceLabelsPrivateFileWithPrivateSticker());

    expect(incomingEvents, isEmpty);
    expect(fakeSyncService.capturedOutgoingEvents, isNull);
    expect(fakeAPI.capturedEventFile, isNull);
  });
}
