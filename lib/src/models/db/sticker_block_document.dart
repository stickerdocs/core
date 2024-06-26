import 'package:stickerdocs_core/src/models/db/db_model.dart';

class StickerBlockDocument extends DBModel {
  static const tableName = 'sticker_block_document';
  static const stickerIdKey = 'sticker_id';
  static const blockDocumentIdKey = 'block_document_id';

  String stickerId;
  String blockDocumentId;

  // Shadow fields
  String? _stickerId;
  String? _blockDocumentId;

  StickerBlockDocument(
      {required this.stickerId, required this.blockDocumentId}) {
    table = tableName;
    commit();
  }

  @override
  Map<String, dynamic> changeset() {
    final changes = <String, dynamic>{};

    if (isNew || stickerId != _stickerId) {
      changes[stickerIdKey] = stickerId;
    }

    if (isNew || blockDocumentId != _blockDocumentId) {
      changes[blockDocumentIdKey] = blockDocumentId;
    }

    populateCreatedAndUpdatedChanges(changes, updatable: false);
    return changes;
  }

  @override
  void commit() {
    _stickerId = stickerId;
    _blockDocumentId = blockDocumentId;
    baseCommit();
  }

  static StickerBlockDocument fromMap(Map<String, dynamic> map) {
    final document = StickerBlockDocument(
      stickerId: map[stickerIdKey],
      blockDocumentId: map[blockDocumentIdKey],
    );

    DBModel.mapBase(document, map);
    return document;
  }

  static List<StickerBlockDocument> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return StickerBlockDocument.fromMap(maps[i]);
    });
  }
}
