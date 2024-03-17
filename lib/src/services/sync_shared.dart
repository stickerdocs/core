import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';

import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/db_schema.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/services/sync.dart';
import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/utils.dart';

import 'package:stickerdocs_core/src/models/db/block.dart';
import 'package:stickerdocs_core/src/models/db/block_document.dart';
import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/db/file_document.dart';
import 'package:stickerdocs_core/src/models/db/shared_object.dart';
import 'package:stickerdocs_core/src/models/db/shared_sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker_block_document.dart';
import 'package:stickerdocs_core/src/models/db/sticker_file_document.dart';
import 'package:stickerdocs_core/src/models/db/trusted_user.dart';
import 'package:stickerdocs_core/src/models/event.dart';
import 'package:stickerdocs_core/src/models/shared_event.dart';
import 'package:stickerdocs_core/src/models/event_file.dart';

class SyncSharedService {
  final DBService _db = GetIt.I.get<DBService>();
  final APIService _api = GetIt.I.get<APIService>();
  final FileService _fileService = GetIt.I.get<FileService>();

  SyncService? _syncServiceInstance;
  AppLogic? _logicInstance;

  final List<String> _fileIdsToDownload = [];
  final List<EventFile> _sharedIncomingEventFiles = [];
  final List<SharedEvent> _sharedEvents = [];
  final List<SharedSticker> _allSharedStickers = [];
  final List<String> _myFileIdsToShare = [];
  final List<String> _myFileIdsToUnshare = [];
  final List<Event> _sharedIncomingEvents = [];
  final List<TrustedUser> _trustedUsersWithNoOutgoingEvents = [];

  late Iterable<Iterable<Event>> _myOutgoingEventGroups;

  final _outgoingEventTypesToProcess = {
    File.tableName,
    FileDocument.tableName,
    Block.tableName,
    BlockDocument.tableName,
    Sticker.tableName,
    StickerFileDocument.tableName,
    StickerBlockDocument.tableName,

    // Note we do not share SharedSticker objects, so this is not in the _permittedIncomingSharedEventTypes list
    // It is here to enable the initial sharing of stickers.
    SharedSticker.tableName,
  };

  final _permittedIncomingSharedEventTypes = {
    File.tableName,
    FileDocument.tableName,
    Block.tableName,
    BlockDocument.tableName,
    Sticker.tableName,
    StickerFileDocument.tableName,
    StickerBlockDocument.tableName,
  };

  SyncService get _syncService {
    _syncServiceInstance ??= GetIt.I.get<SyncService>();
    return _syncServiceInstance!;
  }

  AppLogic get _logic {
    _logicInstance ??= GetIt.I.get<AppLogic>();
    return _logicInstance!;
  }

  Future<List<Event>> getSharedIncomingEvents(
      List<Event> myOutgoingEvents) async {
    // Reset
    // It would be better to use a container class for all this, create a new one here to pass around. Still janky though
    _sharedIncomingEventFiles.clear();
    _sharedEvents.clear();
    _allSharedStickers.clear();
    _myFileIdsToShare.clear();
    _myFileIdsToUnshare.clear();
    _sharedIncomingEvents.clear();
    _trustedUsersWithNoOutgoingEvents.clear();

    // Get the batches of events, after filtering out those that cannot be shared
    _myOutgoingEventGroups = groupEvents(myOutgoingEvents);

    await _populateSharedOutgoingEventFiles();
    return await _acquireSharedIncomingEvents();
  }

  Future<void> _populateSharedOutgoingEventFiles() async {
    _allSharedStickers.addAll(await _db.getSharedStickers());

    // There is nothing to do if we don't have any shared stickers
    if (_allSharedStickers.isEmpty) {
      return;
    }

    await _processEvents();

    if (_sharedEvents.isNotEmpty) {
      await _uploadOutgoingSharedEvents();
    }

    // Even if there are no outgoing events there may be incoming events
    await _processSharedIncomingEventFiles();
  }

  Future<void> _processEvents() async {
    final sharedObjectProcessors = {
      SharedSticker.tableName: _processSharedStickerEvent,
      StickerFileDocument.tableName: _processStickerFileDocumentEvent,
      StickerBlockDocument.tableName: _processStickerBlockDocumentEvent,
    };

    for (final trustedUser in await _db.getTrustedUsers()) {
      final eventsForThisUser = <Event>[];

      // This code is quite horrid

      // Each event group is for a specific object by type+id
      for (final eventGroup in _myOutgoingEventGroups) {
        // TODO: Note we can probably bin off the shared sticker object perhaps - unless we need the shared_by me/read-only mode

        final hasObjectBeenSharedWithThisUser = await _db.isSharedObject(
          eventGroup.first.type,
          eventGroup.first.id,
          trustedUser.id,
        );

        // Are we updating the object or deleting it?
        if (hasObjectBeenSharedWithThisUser) {
          // Propagate the changes to the object
          eventsForThisUser.addAll(eventGroup);

          if (eventGroup.any((event) => event.key == dbModelDeleted)) {
            await _processRemovals(eventGroup, trustedUser);
          }

          continue;
        }

        // Is it a new object to share?
        if (sharedObjectProcessors.containsKey(eventGroup.first.type)) {
          // Process the event
          final additionalEvents =
              await sharedObjectProcessors[eventGroup.first.type]!
                  .call(eventGroup, trustedUser);

          // Add any additional events
          eventsForThisUser.addAll(additionalEvents);
        }
      }

      if (eventsForThisUser.isNotEmpty) {
        _sharedEvents.addAll(eventsForThisUser
            .map((event) => SharedEvent(trustedUser.userId, event)));
      } else {
        _trustedUsersWithNoOutgoingEvents.add(trustedUser);
      }
    }
  }

  Future<List<Event>> _processSharedStickerEvent(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final sharedByMe = eventGroup
            .firstWhere((event) => event.key == SharedSticker.sharedByMeKey)
            .value ==
        '1';

    if (!sharedByMe) {
      // Nothing to do
      return <Event>[];
    }

    final additionalEvents = <Event>[];

    final stickerId = eventGroup
        .firstWhere((event) => event.key == SharedSticker.stickerIdKey)
        .value!;

    final hasStickerBeenSharedWithThisUser = await _db.isSharedObject(
      Sticker.tableName,
      stickerId,
      trustedUser.id,
    );

    // Add the sticker events
    // There could have been changes to the sticker between first share and acceptance
    // Or this could be a sticker deletion?
    if (!hasStickerBeenSharedWithThisUser) {
      final stickerSnapshotEvents =
          await _db.getStickerSnapshotEvents(stickerId);

      additionalEvents.addAll(stickerSnapshotEvents);

      // Mark this sticker as shared
      await _db.save(SharedObject(
          objectType: Sticker.tableName,
          objectId: eventGroup.first.id,
          trustedUserId: trustedUser.id));

      // Share any existing StickerFileDocument objects
      final fileDocuments =
          await _db.getFileDocumentsLabelledWithStickerId(stickerId);
      for (final fileDocument in fileDocuments) {
        final shareFileDocumentEvents = await _getStickerFileDocumentEvents(
            stickerId, fileDocument.id, trustedUser);
        additionalEvents.addAll(shareFileDocumentEvents);
      }
    }

    // Nothing to do
    return additionalEvents;
  }

  Future<List<Event>> _processStickerFileDocumentEvent(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final stickerId = eventGroup
        .firstWhere((event) => event.key == StickerFileDocument.stickerIdKey)
        .value!;

    if (!await _db.isSharedObject(
      Sticker.tableName,
      stickerId,
      trustedUser.id,
    )) {
      // This sticker has not been shared with this user, so ignore this event.
      return <Event>[];
    }

    final fileDocumentId = eventGroup
        .firstWhere(
            (event) => event.key == StickerFileDocument.fileDocumentIdKey)
        .value!;

    return await _getStickerFileDocumentEvents(
        stickerId, fileDocumentId, trustedUser);
  }

  Future<List<Event>> _getStickerFileDocumentEvents(
      String stickerId, String fileDocumentId, TrustedUser trustedUser) async {
    final stickerFileDocument =
        await _db.getStickerFileDocumentFromIds(stickerId, fileDocumentId);

    if (stickerFileDocument == null) {
      // Nothing to do
      return <Event>[];
    }

    final additionalEvents = <Event>[];

    final fileDocumentSnapshotEvents =
        await _db.getFileDocumentSnapshotEvents(fileDocumentId);

    final fileId = fileDocumentSnapshotEvents
        .firstWhere((element) => element.key == FileDocument.fileIdKey)
        .value!;

    final hasStickerFileDocumentBeenSharedWithThisUser =
        await _db.isSharedObject(
      StickerFileDocument.tableName,
      stickerFileDocument.id,
      trustedUser.id,
    );

    final hasFileDocumentBeenSharedWithThisUser = await _db.isSharedObject(
      FileDocument.tableName,
      fileDocumentId,
      trustedUser.id,
    );

    final hasFileBeenSharedWithThisUser = await _db.isSharedObject(
      File.tableName,
      fileId,
      trustedUser.id,
    );

    if (!hasFileBeenSharedWithThisUser) {
      final fileSnapshotEvents = await _db.getFileSnapshotEvents(fileId);
      additionalEvents.addAll(fileSnapshotEvents);

      _myFileIdsToShare.add(fileId);

      await _db.save(SharedObject(
          objectType: File.tableName,
          objectId: fileId,
          trustedUserId: trustedUser.id));
    }

    if (!hasFileDocumentBeenSharedWithThisUser) {
      additionalEvents.addAll(fileDocumentSnapshotEvents);
      await _db.save(SharedObject(
          objectType: FileDocument.tableName,
          objectId: fileDocumentId,
          trustedUserId: trustedUser.id));
    }

    if (!hasStickerFileDocumentBeenSharedWithThisUser) {
      final stickerFileDocumentSnapshotEvents = await _db
          .getStickerFileDocumentSnapshotEvents(stickerFileDocument.id);
      additionalEvents.addAll(stickerFileDocumentSnapshotEvents);
      await _db.save(SharedObject(
          objectType: StickerFileDocument.tableName,
          objectId: stickerFileDocument.id,
          trustedUserId: trustedUser.id));
    }

    return additionalEvents;
  }

  Future<List<Event>> _processStickerBlockDocumentEvent(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final stickerId = eventGroup
        .firstWhere((event) => event.key == StickerBlockDocument.stickerIdKey)
        .value!;

    if (!await _db.isSharedObject(
      Sticker.tableName,
      stickerId,
      trustedUser.id,
    )) {
      // This sticker has not been shared with this user, so ignore this event.
      return <Event>[];
    }

    final blockDocumentId = eventGroup
        .firstWhere(
            (event) => event.key == StickerBlockDocument.blockDocumentIdKey)
        .value!;

    return await _getStickerBlockDocumentEvents(
        stickerId, blockDocumentId, trustedUser);
  }

  Future<List<Event>> _getStickerBlockDocumentEvents(
      String stickerId, String blockDocumentId, TrustedUser trustedUser) async {
    final stickerBlockDocument =
        await _db.getStickerBlockDocumentFromIds(stickerId, blockDocumentId);

    if (stickerBlockDocument == null) {
      // Nothing to do
      return <Event>[];
    }

    final additionalEvents = <Event>[];

    final blockDocumentSnapshotEvents =
        await _db.getBlockDocumentSnapshotEvents(blockDocumentId);

    final blockIds = blockDocumentSnapshotEvents
        .firstWhere((element) => element.key == BlockDocument.blocksKey)
        .value!;

    final hasStickerBlockDocumentBeenSharedWithThisUser =
        await _db.isSharedObject(
      StickerBlockDocument.tableName,
      stickerBlockDocument.id,
      trustedUser.id,
    );

    final hasBlockDocumentBeenSharedWithThisUser = await _db.isSharedObject(
      BlockDocument.tableName,
      blockDocumentId,
      trustedUser.id,
    );

    for (final blockId in BlockDocument.formatBlockIds(blockIds)) {
      final hasBlockBeenSharedWithThisUser = await _db.isSharedObject(
        Block.tableName,
        blockId,
        trustedUser.id,
      );

      if (!hasBlockBeenSharedWithThisUser) {
        final blockSnapshotEvents = await _db.getBlockSnapshotEvents(blockId);
        additionalEvents.addAll(blockSnapshotEvents);

        await _db.save(SharedObject(
            objectType: Block.tableName,
            objectId: blockId,
            trustedUserId: trustedUser.id));
      }
    }

    if (!hasBlockDocumentBeenSharedWithThisUser) {
      additionalEvents.addAll(blockDocumentSnapshotEvents);
      await _db.save(SharedObject(
          objectType: BlockDocument.tableName,
          objectId: blockDocumentId,
          trustedUserId: trustedUser.id));
    }

    if (!hasStickerBlockDocumentBeenSharedWithThisUser) {
      final stickerBlockDocumentSnapshotEvents = await _db
          .getStickerFileDocumentSnapshotEvents(stickerBlockDocument.id);
      additionalEvents.addAll(stickerBlockDocumentSnapshotEvents);
      await _db.save(SharedObject(
          objectType: StickerBlockDocument.tableName,
          objectId: stickerBlockDocument.id,
          trustedUserId: trustedUser.id));
    }

    return additionalEvents;
  }

  Future<List<Event>> _acquireSharedIncomingEvents() async {
    await Future.forEach(
        _sharedIncomingEventFiles, _acquireIncomingSharedEventFile);
    return _sharedIncomingEvents;
  }

  Future<void> _acquireIncomingSharedEventFile(EventFile eventFile) async {
    final incomingEvents =
        await _syncService.acquireAndLoadEventFile(eventFile);

    final filteredIncomingEvents =
        incomingEvents.where(_isIncomingEventValid).toList();

    _sharedIncomingEvents.addAll(filteredIncomingEvents);

    await markIncomingEventsAsSharedObjects(
        _sharedIncomingEvents, eventFile.sourceUserId!);

    await _populateFileIdsToDownload(filteredIncomingEvents, eventFile);

    _setSourceUserIdOnIncomingFileEvents(
        filteredIncomingEvents, eventFile.sourceUserId!);
  }

  Future<void> _populateFileIdsToDownload(
      List<Event> filteredIncomingEvents, EventFile eventFile) async {
    final fileIdsToDownload = filteredIncomingEvents
        .where((element) => element.type == File.tableName)
        .map((element) => element.id)
        .toSet();

    // Only download files we do not already have
    final allFileIds = await _db.getAllFileIds();
    fileIdsToDownload.removeAll(allFileIds);

    _fileIdsToDownload.clear();
    _fileIdsToDownload.addAll(fileIdsToDownload);
  }

  Future<void> _uploadOutgoingSharedEvents() async {
    for (final eventsGroupedByUserId
        in _sharedEvents.groupListsBy((element) => element.userId).entries) {
      final userIdSharingWith = eventsGroupedByUserId.key;
      final outgoingEventsForThisUser = eventsGroupedByUserId.value
          .map((sharedEvent) => sharedEvent.event)
          .toList();
      final incomingEventFilesToProcess =
          await _uploadOutgoingSharedEventsForUser(
              userIdSharingWith,
              outgoingEventsForThisUser,
              _myFileIdsToShare,
              _myFileIdsToUnshare);

      if (incomingEventFilesToProcess == null) {
        logger.d('incomingEventFilesToProcess was null');
        // _syncResult is already set to SyncResult.apiError
        return;
      }

      _addSharedIncomingEventFiles(
          incomingEventFilesToProcess, userIdSharingWith);
    }
  }

  void _addSharedIncomingEventFiles(
      List<EventFile> incomingEventsToProcess, String userIdSharingWith) {
    for (final incomingEvent in incomingEventsToProcess) {
      incomingEvent.sourceUserId = userIdSharingWith;
    }

    _sharedIncomingEventFiles.addAll(incomingEventsToProcess);
  }

  Future<void> _processSharedIncomingEventFiles() async {
    for (final trustedUser in _trustedUsersWithNoOutgoingEvents) {
      final incomingEventFilesToProcess =
          await _api.syncShared(trustedUser.userId);

      if (incomingEventFilesToProcess == null) {
        logger.d('incomingEventFilesToProcess was null');
        _syncService.syncResult = SyncResult.apiError;
        return;
      }

      _addSharedIncomingEventFiles(
          incomingEventFilesToProcess, trustedUser.userId);
    }
  }

  Iterable<Iterable<Event>> groupEvents(Iterable<Event> events) {
    final eventGroups = <String, List<Event>>{};

    for (final event in events) {
      if (_outgoingEventTypesToProcess.contains(event.type)) {
        // Combine the type + ID just in case we have any ID collisions across types
        final key = '${event.type}${event.id}';
        eventGroups[key] ??= [];
        eventGroups[key]!.add(event);
      }
    }

    // Just return the groups as this key (type + ID) is not useful elsewhere
    return eventGroups.values;
  }

  void _setSourceUserIdOnIncomingFileEvents(
      List<Event> incomingEvents, String sourceUserId) {
    final eventsToProcess = incomingEvents.where((event) =>
        event.type == File.tableName && _fileIdsToDownload.contains(event.id));

    final additionalEvents = <Event>[];
    final processedFileIds = <String>[];

    for (final incomingEvent in eventsToProcess) {
      if (!processedFileIds.contains(incomingEvent.id)) {
        additionalEvents.add(Event(
          incomingEvent.timestamp,
          latestDatabaseVersion,
          File.tableName,
          incomingEvent.id,
          File.sourceUserIdKey,
          sourceUserId,
        ));

        processedFileIds.add(incomingEvent.id);
      }
    }

    _sharedIncomingEvents.addAll(additionalEvents);
  }

  Future<void> markIncomingEventsAsSharedObjects(
      List<Event> incomingEvents, String userId) async {
    final trustedUser = await _db.getTrustedUserByUserId(userId);

    if (trustedUser == null) {
      logger.e('No trusted user found');
      return;
    }

    for (final eventGroup in groupEvents(incomingEvents)) {
      final hasObjectBeenSharedWithThisUser = await _db.isSharedObject(
        eventGroup.first.type,
        eventGroup.first.id,
        trustedUser.id,
      );

      if (!hasObjectBeenSharedWithThisUser) {
        _db.save(SharedObject(
          objectType: eventGroup.first.type,
          objectId: eventGroup.first.id,
          trustedUserId: trustedUser.id,
        ));
      }
    }
  }

  Future<List<EventFile>?> _uploadOutgoingSharedEventsForUser(
      String userId,
      List<Event> sharedOutgoingEvents,
      List<String> fileIdsToShare,
      List<String> fileIdsToUnshare) async {
    final outgoingEventFile = await _syncService
        .createAndUploadEventFile(sharedOutgoingEvents, userId: userId);

    if (outgoingEventFile == null) {
      logger.d('outgoingEventFile was null');
      return null;
    }

    // Attach files to share/unshare
    outgoingEventFile.fileIdsToShare = fileIdsToShare;
    outgoingEventFile.fileIdsToUnshare = fileIdsToUnshare;

    final eventFiles = await _api.syncShared(userId, outgoingEventFile);

    if (eventFiles == null) {
      logger.d('eventFiles was null');
      _syncService.syncResult = SyncResult.apiError;
      return null;
    }

    return eventFiles;
  }

  bool _isIncomingEventValid(Event incomingEvent) {
    // Shared events can only be for a restricted selection of types
    if (!_permittedIncomingSharedEventTypes.contains(incomingEvent.type)) {
      logger.w('Ignoring incoming event of type \'${incomingEvent.type}\'');
      return false;
    }

    return true;
  }

  Future<void> uploadSharedFilesNotInMyAccount() async {
    for (final fileId in _fileIdsToDownload) {
      final file = await _db.getFileById(fileId);

      if (file != null) {
        await _addFileToMyAccount(file);
      }
    }
  }

  Future<void> _addFileToMyAccount(File file) async {
    await _fileService.downloadFile(file);

    // Burn the encryption key so a new one will be generated on upload
    file.encryptionKey = null;

    await _fileService.uploadFile(file);

    // Save space on mobile devices once we have uploaded the file to our account
    if (isMobile) {
      await _logic.purgeFile(file);
    }
  }

  Future<void> markIncomingEventsSuccessfullySynchronised() async {
    for (final eventFile in _sharedIncomingEventFiles) {
      if (!await _api.syncSuccess(eventFile)) {
        _syncService.syncResult = SyncResult.apiError;
        return;
      }
    }
  }

  Future<void> _processRemovals(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    if (eventGroup.first.type == File.tableName) {
      return await _processRemoveFile(eventGroup.first.id, trustedUser);
    }

    if (eventGroup.first.type == FileDocument.tableName) {
      return await _processRemoveFileDocument(eventGroup, trustedUser);
    }

    if (eventGroup.first.type == StickerFileDocument.tableName) {
      return await _processRemoveStickerFileDocument(eventGroup, trustedUser);
    }

    if (eventGroup.first.type == Sticker.tableName) {
      return await _processRemoveSticker(eventGroup, trustedUser);
    }
  }

  Future<void> _processRemoveFileDocument(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final fileDocument = await _db.getFileDocumentById(eventGroup.first.id);

    await _db.delete(SharedObject(
        objectType: FileDocument.tableName,
        objectId: eventGroup.first.id,
        trustedUserId: trustedUser.id));

    await _processRemoveFile(fileDocument!.fileId, trustedUser);
  }

  Future<void> _processRemoveStickerFileDocument(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final stickerFileDocument =
        await _db.getStickerFileDocumentById(eventGroup.first.id);
    final fileDocument =
        await _db.getFileDocumentById(stickerFileDocument!.fileDocumentId);

    await _db.delete(SharedObject(
        objectType: StickerFileDocument.tableName,
        objectId: eventGroup.first.id,
        trustedUserId: trustedUser.id));

    await _db.delete(SharedObject(
        objectType: FileDocument.tableName,
        objectId: fileDocument!.id,
        trustedUserId: trustedUser.id));

    await _processRemoveFile(fileDocument.fileId, trustedUser);
  }

  Future<void> _processRemoveSticker(
      Iterable<Event> eventGroup, TrustedUser trustedUser) async {
    final sharedFiles = await _db.getSharedFilesLabelledWithStickerId(
        eventGroup.first.id, trustedUser);

    await _db.delete(SharedObject(
        objectType: Sticker.tableName,
        objectId: eventGroup.first.id,
        trustedUserId: trustedUser.id));

    for (final file in sharedFiles) {
      await _processRemoveFile(file.id, trustedUser);
    }
  }

  Future<void> _processRemoveFile(
      String fileId, TrustedUser trustedUser) async {
    _myFileIdsToUnshare.add(fileId);
    await _db.delete(SharedObject(
        objectType: File.tableName,
        objectId: fileId,
        trustedUserId: trustedUser.id));
  }
}
