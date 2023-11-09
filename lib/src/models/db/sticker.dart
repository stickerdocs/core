import 'dart:convert';
import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/utils.dart';

class Sticker extends DBModel {
  static const tableName = 'sticker';

  String name;
  String? style = 'border';
  Uint8List? svg;

  // Shadow fields
  String? _name;
  String? _style;
  Uint8List? _svg;

  Sticker({required this.name}) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || name != _name) {
      changes['name'] = name;
    }

    if (isNew && style != null || style != _style) {
      changes['style'] = style;
    }

    if (isNew && svg != null || svg != _svg) {
      changes['svg'] = uint8ListToBase64(svg!);
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _name = name;
    _style = style;
    _svg = svg;
    baseCommit(isNew: isNew);
  }

  static Sticker fromMap(Map<String, dynamic> map) {
    var sticker = Sticker(name: map['name']);

    sticker.style = map['style'];
    sticker.svg = base64ToUint8List(map['svg']);

    DBModel.mapBase(sticker, map);
    return sticker;
  }

  static List<Sticker> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return Sticker.fromMap(maps[i]);
    });
  }

  Uri getSvgDataUri() {
    final base64StickerData = base64Encode(svg!).toString();
    return Uri.parse('data:image/svg+xml;base64,$base64StickerData');
  }
}
