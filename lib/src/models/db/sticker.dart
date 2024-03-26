import 'dart:convert';
import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/svg_security.dart';
import 'package:stickerdocs_core/src/utils.dart';

class Sticker extends DBModel {
  static const tableName = 'sticker';

  String name;
  String? style = 'border';
  Uint8List? _svg;

  // Shadow fields
  String? _name;
  String? _style;
  Uint8List? __svg;

  Sticker({required this.name}) {
    table = tableName;
    commit();
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

    if (isNew && _svg != null || _svg != __svg) {
      changes['svg'] = getBase64SVG();
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit() {
    _name = name;
    _style = style;
    __svg = _svg;
    baseCommit();
  }

  static Sticker fromMap(Map<String, dynamic> map) {
    var sticker = Sticker(name: map['name']);

    sticker.style = map['style'];

    // We don't need to re-sanitise the data for performance when loading from DB
    sticker._svg = base64ToUint8List(map['svg']);

    DBModel.mapBase(sticker, map);
    return sticker;
  }

  static List<Sticker> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return Sticker.fromMap(maps[i]);
    });
  }

  void setSVG(Uint8List svg) {
    if (isSafeSVG(svg)) {
      _svg = svg;
    }
  }

  String getBase64SVG() {
    return uint8ListToBase64(_svg!);
  }

  Uri? getSVGDataUri() {
    if (_svg == null) {
      return null;
    }
    
    // This is the regular B64-encoding, not the URL-safe one
    // Do not be tempted to refactor with getBase64Svg()
    final base64StickerData = base64Encode(_svg!).toString();
    return Uri.parse('data:image/svg+xml;base64,$base64StickerData');
  }
}
