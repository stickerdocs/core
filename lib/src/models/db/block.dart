import 'package:stickerdocs_core/src/models/db/db_model.dart';

enum BlockType { file, evernoteData }

extension BlockTypeExtensions on BlockType {
  String format() {
    return toString().split('.')[1];
  }
}

BlockType _blockTypeFromString(String val) {
  if (val == BlockType.file.format()) {
    return BlockType.file;
  }

  if (val == BlockType.evernoteData.format()) {
    return BlockType.evernoteData;
  }

  throw ('BlockType not supported');
}

class Block extends DBModel {
  static const String tableName = 'block';
  static const String typeKey = 'type';
  static const String dataKey = 'data';

  BlockType type;
  String? data;

  // Shadow fields
  BlockType? _type;
  String? _data;

  Block({required this.type}) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || type != _type) {
      changes[typeKey] = type.format();
    }

    if (isNew && data != null || data != _data) {
      changes[dataKey] = data;
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _type = type;
    _data = data;
    baseCommit(isNew: isNew);
  }

  static Block fromMap(Map<String, dynamic> map) {
    var block = Block(type: _blockTypeFromString(map[typeKey]));
    block.data = map[dataKey];

    DBModel.mapBase(block, map);
    return block;
  }

  static List<Block> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return Block.fromMap(maps[i]);
    });
  }
}
