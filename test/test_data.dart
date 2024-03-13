import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/block_document.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/db/file_document.dart';
import 'package:stickerdocs_core/src/models/db/invited_user.dart';
import 'package:stickerdocs_core/src/models/db/shared_object.dart';
import 'package:stickerdocs_core/src/models/db/shared_sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker_file_document.dart';
import 'package:stickerdocs_core/src/models/db/trusted_user.dart';
import 'package:stickerdocs_core/src/models/event.dart';
import 'package:stickerdocs_core/src/models/event_file.dart';

const aliceUserId = 'user.alice';
const bobUserId = 'user.bob';

Sticker? _aliceSticker;

Sticker get aliceSticker {
  if (_aliceSticker == null) {
    _aliceSticker = Sticker(name: 'alice.sticker.name');
    _aliceSticker!.style = 'border';
  }

  return _aliceSticker!;
}

final aliceTrustsBob = TrustedUser(
  userId: bobUserId,
  name: 'bob.trusted_user.name',
  email: 'bob.trusted_user.email',
  publicKey: Uint8List.fromList([0x87, 0xfe]),
);

final bobTrustsAlice = TrustedUser(
  userId: aliceUserId,
  name: 'alice.trusted_user.name',
  email: 'alice.trusted_user.email',
  publicKey: Uint8List.fromList([0x90, 0x11]),
);

final stickerSharedByAliceToBob = SharedSticker(
  stickerId: aliceSticker.id,
  trustedUserId: aliceTrustsBob.id,
  sharedByMe: true,
  ignoreExternalEvents: false,
);

final bobsCopyOfAlicesSharedSticker = SharedSticker(
  stickerId: aliceSticker.id,
  trustedUserId: bobTrustsAlice.id,
  sharedByMe: false,
  ignoreExternalEvents: false,
);

FileDocument? _fileDocument;

FileDocument get fileDocument {
  if (_fileDocument == null) {
    _fileDocument = FileDocument(fileId: file.id);
    _fileDocument!.title = 'file_document.title';
  }

  return _fileDocument!;
}

final file = File(
  name: 'file.name',
  size: 34,
  sha256: 'file.sha256',
  contentType: 'file.content_type',
  uploaded: false,
  downloaded: false,
);

StickerFileDocument stickerFileDocument = StickerFileDocument(
    stickerId: aliceSticker.id, fileDocumentId: fileDocument.id);

final stickerSnapshotEvents = [
  Event('timestamp.1', 1, Sticker.tableName, aliceSticker.id, 'name',
      aliceSticker.name),
  Event('timestamp.1', 1, Sticker.tableName, aliceSticker.id, 'style',
      aliceSticker.style!),
];

final fileSnapshotEvents = [
  Event('timestamp.1', 1, File.tableName, file.id, 'name', file.name!),
  Event('timestamp.1', 1, File.tableName, file.id, 'sha256', file.sha256!),
];

final fileDocumentSnapshotEvents = [
  Event('timestamp.2', 1, FileDocument.tableName, fileDocument.id, 'file_id',
      fileDocument.fileId),
  Event('timestamp.2', 1, FileDocument.tableName, fileDocument.id, 'title',
      fileDocument.title!),
];

final stickerFileDocumentSnapshotEvents = [
  Event('timestamp.3', 1, StickerFileDocument.tableName, stickerFileDocument.id,
      'sticker_id', stickerFileDocument.stickerId),
  Event('timestamp.3', 1, StickerFileDocument.tableName, stickerFileDocument.id,
      'file_document_id', stickerFileDocument.fileDocumentId),
];

Sticker? _privateSticker;

Sticker get privateSticker {
  if (_privateSticker == null) {
    _privateSticker = Sticker(name: 'private.sticker.name');
    _privateSticker!.style = 'border';
  }

  return _privateSticker!;
}

final privateFile = File(
  name: 'private.file.name',
  size: 102,
  sha256: 'private.file.sha256',
  contentType: 'private.file.content_type',
  uploaded: true,
  downloaded: false,
);

FileDocument? _privateFileDocument;

FileDocument get privateFileDocument {
  if (_privateFileDocument == null) {
    _privateFileDocument = FileDocument(fileId: privateFile.id);
    _privateFileDocument!.title = 'private_file_document.title';
  }

  return _privateFileDocument!;
}

StickerFileDocument privateStickerFileDocument = StickerFileDocument(
    stickerId: privateSticker.id, fileDocumentId: privateFileDocument.id);

final privateStickerSnapshotEvents = [
  Event('timestamp.1', 1, Sticker.tableName, privateSticker.id, 'name',
      privateSticker.name),
  Event('timestamp.1', 1, Sticker.tableName, privateSticker.id, 'style',
      privateSticker.style!),
];

final privateFileSnapshotEvents = [
  Event('timestamp.1', 1, File.tableName, privateFile.id, 'name',
      privateFile.name!),
  Event('timestamp.1', 1, File.tableName, privateFile.id, 'sha256',
      privateFile.sha256!),
];

final privateFileDocumentSnapshotEvents = [
  Event('timestamp.2', 1, FileDocument.tableName, privateFileDocument.id,
      'file_id', privateFileDocument.fileId),
  Event('timestamp.2', 1, FileDocument.tableName, privateFileDocument.id,
      'title', privateFileDocument.title!),
];

final privateStickerFileDocumentSnapshotEvents = [
  Event(
      'timestamp.3',
      1,
      StickerFileDocument.tableName,
      privateStickerFileDocument.id,
      'sticker_id',
      privateStickerFileDocument.stickerId),
  Event(
      'timestamp.3',
      1,
      StickerFileDocument.tableName,
      privateStickerFileDocument.id,
      'file_document_id',
      privateStickerFileDocument.fileDocumentId),
];

final eventFile = EventFile(
  firstTimestamp: 'event_file.first_timestamp',
  fileId: 'event_file.file_id',
  fileEncryptedKey: Uint8List.fromList([0x70, 0x25]),
);

List<Event> initialStickerShareEventsFromAlice() {
  return stickerSnapshotEvents +
      fileSnapshotEvents +
      fileDocumentSnapshotEvents +
      stickerFileDocumentSnapshotEvents;
}

final noise = [
  Event('timestamp.1', 1, 'type.1', 'id.1', 'key.1', 'value.1'),
  Event('timestamp.2', 1, 'type.2', 'id.2', 'key.2', 'value.2'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3a', 'value.3a'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3b', 'value.3b'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3c', 'value.3c'),
  Event('timestamp.4', 1, 'type.4', 'id.4', 'key.4a', 'value.4a'),
  Event('timestamp.4', 1, 'type.4', 'id.4', 'key.4b', 'value.4b'),
];

final moreNoise = [
  Event('timestamp.6', 1, 'type.5', 'id.5a', 'key.5', 'value.5'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3d', 'value.3d'),
  Event('timestamp.6', 1, 'type.5', 'id.5b', 'key.5', 'value.5'),
];

final aliceInitialStickerShareOutgoingEvents = [
  // Noise
  Event('timestamp.1', 1, 'type.1', 'id.1', 'key.1', 'value.1'),
  Event('timestamp.2', 1, 'type.2', 'id.2', 'key.2', 'value.2'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3a', 'value.3a'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3b', 'value.3b'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3c', 'value.3c'),
  Event('timestamp.4', 1, 'type.4', 'id.4', 'key.4a', 'value.4a'),
  Event('timestamp.4', 1, 'type.4', 'id.4', 'key.4b', 'value.4b'),

  // Alice shares a sticker with Bob
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'sticker_id', stickerSharedByAliceToBob.stickerId),
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'trusted_user_id', stickerSharedByAliceToBob.trustedUserId),
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'shared_by_me', stickerSharedByAliceToBob.sharedByMe ? '1' : '0'),
  Event(
      'timestamp.5',
      1,
      SharedSticker.tableName,
      stickerSharedByAliceToBob.id,
      'ignore_external_events',
      stickerSharedByAliceToBob.ignoreExternalEvents ? '1' : '0'),

  // Noise
  Event('timestamp.6', 1, 'type.5', 'id.5a', 'key.5', 'value.5'),
  Event('timestamp.3', 1, 'type.3', 'id.3', 'key.3d', 'value.3d'),
  Event('timestamp.6', 1, 'type.5', 'id.5b', 'key.5', 'value.5'),
];

final aliceSharedStickerEvents = [
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'sticker_id', stickerSharedByAliceToBob.stickerId),
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'trusted_user_id', stickerSharedByAliceToBob.trustedUserId),
  Event('timestamp.5', 1, SharedSticker.tableName, stickerSharedByAliceToBob.id,
      'shared_by_me', stickerSharedByAliceToBob.sharedByMe ? '1' : '0'),
  Event(
      'timestamp.5',
      1,
      SharedSticker.tableName,
      stickerSharedByAliceToBob.id,
      'ignore_external_events',
      stickerSharedByAliceToBob.ignoreExternalEvents ? '1' : '0'),
];

final groupTestFilterEvents = [
  Event('timestamp.1', 1, Sticker.tableName, 'id.1', 'key.1', 'value.1'),
  Event('timestamp.2', 1, File.tableName, 'id.2', 'key.2', 'value.2'),
  Event('timestamp.3', 1, FileDocument.tableName, 'id.3', 'key.3a', 'value.3a'),
  Event('timestamp.3', 1, FileDocument.tableName, 'id.3', 'key.3b', 'value.3b'),
  Event('timestamp.3', 1, FileDocument.tableName, 'id.3', 'key.3c', 'value.3c'),
  Event(
      'timestamp.4', 1, BlockDocument.tableName, 'id.4', 'key.4a', 'value.4a'),
  Event(
      'timestamp.4', 1, BlockDocument.tableName, 'id.4', 'key.4b', 'value.4b'),
  Event('timestamp.4', 1, SharedObject.tableName, 'id.4', 'key.4b',
      'should be ignored'),
  Event('timestamp.5', 1, TrustedUser.tableName, 'id.4', 'key.4b',
      'should be ignored'),
  Event('timestamp.5', 1, StickerFileDocument.tableName, 'id.5a', 'key.5',
      'value.5'),
  Event('timestamp.3', 1, FileDocument.tableName, 'id.3', 'key.3d', 'value.3d'),
  Event('timestamp.5', 1, StickerFileDocument.tableName, 'id.5b', 'key.5',
      'value.5'),
  Event('timestamp.3', 1, InvitedUser.tableName, 'id.4', 'key.4b',
      'should be ignored'),
];

List<Event> aliceLabelsAnExistingFileWithASharedStickerEvents() {
  return noise + stickerFileDocumentSnapshotEvents + moreNoise;
}

List<Event> sharedEventsFromAliceAfterSharingFile() {
  return fileSnapshotEvents +
      fileDocumentSnapshotEvents +
      stickerFileDocumentSnapshotEvents;
}

List<Event> deleteFileEvents = [
  Event('timestamp.4', 1, File.tableName, file.id, 'deleted', '1')
];

List<Event> aliceDeletesAFileEvents() {
  return noise + deleteFileEvents + moreNoise;
}

List<Event> deleteFileDocumentEvents = [
  Event(
      'timestamp.4', 1, FileDocument.tableName, fileDocument.id, 'deleted', '1')
];

List<Event> aliceDeletesAFileDocumentEvents() {
  return noise + deleteFileDocumentEvents + moreNoise;
}

List<Event> deleteStickerFileDocumentEvents = [
  Event('timestamp.4', 1, StickerFileDocument.tableName, stickerFileDocument.id,
      'deleted', '1')
];

List<Event> aliceDeletesAStickerFileDocumentEvents() {
  return noise + deleteStickerFileDocumentEvents + moreNoise;
}

List<Event> deleteStickerEvents = [
  Event('timestamp.4', 1, Sticker.tableName, aliceSticker.id, 'deleted', '1')
];

List<Event> aliceDeletesAStickerEvents() {
  return noise + deleteStickerEvents + moreNoise;
}

List<Event> aliceLabelsPrivateFileWithPrivateSticker() {
  return privateStickerSnapshotEvents +
      privateFileSnapshotEvents +
      privateFileDocumentSnapshotEvents +
      privateStickerFileDocumentSnapshotEvents;
}
