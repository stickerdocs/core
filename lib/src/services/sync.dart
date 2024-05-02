import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart';

import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/event.dart';
import 'package:stickerdocs_core/src/models/event_file.dart';
import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/main.dart';
import 'package:stickerdocs_core/src/services/sync_shared.dart';
import 'package:stickerdocs_core/src/utils.dart';
import 'package:stickerdocs_core/src/validation.dart';

enum SyncResult {
  notStarted,
  inProgress,
  apiError,
  cryptoError,
}

class SyncService {
  final DBService _db = GetIt.I.get<DBService>();
  final APIService _api = GetIt.I.get<APIService>();
  final FileService _fileService = GetIt.I.get<FileService>();
  final SyncSharedService _sharedSync = GetIt.I.get<SyncSharedService>();
  AppLogic? _logicInstance;
  final List<io.File> _temporaryFiles = [];
  List<EventFile>? _myIncomingEventFiles;
  List<Event>? _myOutgoingEvents;
  SyncResult syncResult = SyncResult.notStarted;

  AppLogic get _logic {
    _logicInstance ??= GetIt.I.get<AppLogic>();
    return _logicInstance!;
  }

  Future<bool> sync() async {
    syncResult = SyncResult.inProgress;
    _myIncomingEventFiles = null;
    _myOutgoingEvents = null;

    await _sync();

    // Finally do some cleaning up
    await _cleanup();

    return syncResult == SyncResult.inProgress;
  }

  Future<void> _sync() async {
    await _populateMyOutgoingEvents();

    final myIncomingEvents = await getMyIncomingEvents();

    if (syncResult != SyncResult.inProgress) {
      return;
    }

    final sharedIncomingEvents =
        await _sharedSync.getSharedIncomingEvents(_myOutgoingEvents!);

    logger.t(sharedIncomingEvents);

    if (syncResult != SyncResult.inProgress) {
      return;
    }

    await applyIncomingEvents(myIncomingEvents, sharedIncomingEvents);
    await _sharedSync.uploadSharedFilesNotInMyAccount();
    await _sharedSync.markIncomingEventsSuccessfullySynchronised();
    await markIncomingEventsSuccessfullySynchronised();
  }

  Future<void> _populateMyOutgoingEvents() async {
    // TODO: bail if over quota
    // If we do not have an active subscription then don't send any events
    // if (!_logic.subscriptionActive.value) {
    //   _myOutgoingEvents = <Event>[];
    //   return;
    // }

    _myOutgoingEvents = await _db.getOutgoingEvents();
  }

  Future<List<Event>> getMyIncomingEvents() async {
    await _populateMyIncomingEventFiles();

    final List<Event> events = [];

    if (syncResult != SyncResult.inProgress) {
      return events;
    }

    for (final eventFile in _myIncomingEventFiles!) {
      events.addAll(await acquireAndLoadEventFile(eventFile));
    }

    return events;
  }

  Future<void> _populateMyIncomingEventFiles() async {
    _myIncomingEventFiles =
        await (_myOutgoingEvents!.isEmpty ? _api.sync() : _sendMyEvents());

    // Was there an issue sending my events?
    if (_myIncomingEventFiles == null) {
      logger.e('_myIncomingEventFiles is null');
      syncResult = SyncResult.apiError;
    }
  }

  Future<List<EventFile>?> _sendMyEvents() async {
    final outgoingEventFile =
        await createAndUploadEventFile(_myOutgoingEvents!);

    if (outgoingEventFile == null) {
      logger.e('outgoingEventFile is null');
      return null;
    }

    final incomingEventFiles = await _api.sync(outgoingEventFile);

    // Only if sync was successful
    if (incomingEventFiles != null) {
      await _db.markEventsUploaded(_myOutgoingEvents!);
    }

    return incomingEventFiles;
  }

  Future<EventFile?> createAndUploadEventFile(List<Event> events,
      {String? userId}) async {
    // Hmm is it possible this hash may already exist and we will be deleting it due to the next line?
    final outgoingEventFile = await _logic.createOrGetExistingFileFromBytes(
        stringToUint8List(jsonEncode(events)), null);

    _temporaryFiles.add(outgoingEventFile.getFile());

    // Set the content type to stickerdocs/eventdata
    // so it will not be saved in the event table
    outgoingEventFile.contentType = CustomContentType.eventData.format();

    final uploadSuccess = await _fileService.uploadFile(outgoingEventFile);

    if (!uploadSuccess) {
      logger.e('Upload was not successful');
      syncResult = SyncResult.apiError;
      return null;
    }

    // Encrypt the event file encryption key
    // 72 bytes
    final outgoingEventFileEncryptedKey =
        await _encryptOutgoingEventFile(outgoingEventFile, userId);

    if (outgoingEventFileEncryptedKey == null) {
      logger.e('Could not encrypt file');
      syncResult = SyncResult.cryptoError;
      return null;
    }

    return EventFile(
        firstTimestamp: events.first.timestamp,
        fileId: outgoingEventFile.id,
        fileEncryptedKey: outgoingEventFileEncryptedKey);
  }

  Future<List<Event>> acquireAndLoadEventFile(EventFile eventFile) async {
    // Decrypt the encryption key
    final decryptedEncryptionKey = await _decryptIncomingEventFile(eventFile);

    if (decryptedEncryptionKey == null) {
      logger.e('Could not decrypt incoming event file');
      return <Event>[];
    }

    await _fileService.downloadFileById(
        eventFile.fileId, decryptedEncryptionKey, eventFile.sourceUserId);

    final incomingEventFile = io.File(join(config.dataPath, eventFile.fileId));
    _temporaryFiles.add(incomingEventFile);

    final eventData = await incomingEventFile.readAsBytes();
    return Event.deserialize(uint8ListToString(eventData));
  }

  Future<Uint8List?> _decryptIncomingEventFile(EventFile eventFile) async {
    if (eventFile.sourceUserId == null) {
      return await crypto.decryptFromMe(eventFile.fileEncryptedKey);
    }

    // Get the user's public key
    final trustedUser =
        await _db.getTrustedUserByUserId(eventFile.sourceUserId!);

    return await crypto.decryptFromOtherUser(
        eventFile.fileEncryptedKey, trustedUser!.publicKey);
  }

  Future<Uint8List?> _encryptOutgoingEventFile(
      File outgoingEventFile, String? userId) async {
    if (userId == null) {
      return await crypto.encryptForMe(outgoingEventFile.encryptionKey!);
    }

    // Get the user's public key
    final trustedUser = await _db.getTrustedUserByUserId(userId);

    // Encrypt the event file encryption key
    // 72 bytes
    return await crypto.encryptForOtherUser(
        outgoingEventFile.encryptionKey!, trustedUser!.publicKey);
  }

  Future<void> applyIncomingEvents(
      List<Event> myIncomingEvents, List<Event> sharedIncomingEvents) async {
    final securityFilteredIncomingEvents =
        (myIncomingEvents + sharedIncomingEvents).where(isIncomingEventValid);

    await _db.applyIncomingEvents(securityFilteredIncomingEvents);
  }

  bool isIncomingEventValid(Event incomingEvent) {
    if (!isSDIDValid(incomingEvent.id)) {
      logger.w(
          'Ignoring incoming event of type ${incomingEvent.type} due to invalid ID: \'${incomingEvent.id}\'');
      return false;
    }

    if (!isEventKeyValid(incomingEvent.key)) {
      logger.w(
          'Ignoring incoming event of type ${incomingEvent.type} due to invalid key: \'${incomingEvent.key}\'');
      return false;
    }

    return true;
  }

  Future<void> markIncomingEventsSuccessfullySynchronised() async {
    for (final eventFile in _myIncomingEventFiles!) {
      if (!await _api.syncSuccess(eventFile)) {
        logger.e('Sync API call was unsuccessful');
        syncResult = SyncResult.apiError;
        return;
      }
    }
  }

  Future<void> _cleanup() async {
    for (final file in _temporaryFiles) {
      try {
        await file.delete();
      } catch (exception) {
        // Ignore
      }
    }

    _temporaryFiles.clear();

    await _db.cleanupSyncFilesAndEvents();
  }
}
