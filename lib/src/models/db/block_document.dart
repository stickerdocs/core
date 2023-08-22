import 'package:stickerdocs_core/src/models/db/document.dart';
import 'package:stickerdocs_core/src/models/db/db_model.dart';

class BlockDocument extends Document implements DBModel {
  static const String tableName = 'block_document';
  static const String blocksKey = 'blocks';

  String? blocks;

  // Shadow fields
  String? _blocks;

  BlockDocument() {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || blocks != _blocks) {
      changes[blocksKey] = blocks;
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _blocks = blocks;
    baseCommit(isNew: isNew);
  }

  static BlockDocument fromMap(Map<String, dynamic> map) {
    final document = BlockDocument();
    document.blocks = map[blocksKey];

    Document.mapBase(document, map);
    return document;
  }

  static List<BlockDocument> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return BlockDocument.fromMap(maps[i]);
    });
  }

  getBlockIds() {
    return formatBlockIds(blocks!);
  }

  static formatBlockIds(String blockIds) {
    return blockIds.split(',');
  }
}
