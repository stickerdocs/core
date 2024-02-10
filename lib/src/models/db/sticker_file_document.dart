import 'package:stickerdocs_core/src/models/db/db_model.dart';

class StickerFileDocument extends DBModel {
  static const tableName = 'sticker_file_document';
  static const stickerIdKey = 'sticker_id';
  static const fileDocumentIdKey = 'file_document_id';

  String stickerId;
  String fileDocumentId;

  // Shadow fields
  String? _stickerId;
  String? _fileDocumentId;

  StickerFileDocument({required this.stickerId, required this.fileDocumentId}) {
    table = tableName;
    commit();
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || stickerId != _stickerId) {
      changes[stickerIdKey] = stickerId;
    }

    if (isNew || fileDocumentId != _fileDocumentId) {
      changes[fileDocumentIdKey] = fileDocumentId;
    }

    populateCreatedAndUpdatedChanges(changes, updatable: false);
    return changes;
  }

  @override
  void commit() {
    _stickerId = stickerId;
    _fileDocumentId = fileDocumentId;
    baseCommit();
  }

  static StickerFileDocument fromMap(Map<String, dynamic> map) {
    final document = StickerFileDocument(
      stickerId: map[stickerIdKey],
      fileDocumentId: map[fileDocumentIdKey],
    );

    DBModel.mapBase(document, map);
    return document;
  }

  static List<StickerFileDocument> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return StickerFileDocument.fromMap(maps[i]);
    });
  }
}
