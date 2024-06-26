import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:stickerdocs_core/src/main.dart';
import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/utils.dart';

class File extends DBModel {
  String? name;
  int? size;
  String? sha256;
  String? contentType;
  Uint8List? encryptionKey;
  String? sourceUserId;
  bool? uploaded;
  bool downloaded;
  bool notFound;

  // Shadow fields
  String? _name;
  int? _size;
  String? _sha256;
  String? _contentType;
  Uint8List? _encryptionKey;
  String? _sourceUserId;
  bool? _uploaded;

  static const tableName = 'file';
  static const nameKey = 'name';
  static const sizeKey = 'size';
  static const sha256Key = 'sha256';
  static const contentTypeKey = 'content_type';
  static const sourceUserIdKey = 'source_user_id';
  static const encryptionKeyKey = 'encryption_key';
  static const uploadedKey = 'uploaded';

  File({
    required this.name,
    required this.size,
    required this.sha256,
    required this.contentType,
    required this.uploaded,
    required this.downloaded,
    required this.notFound,
  }) {
    table = tableName;
    commit();
  }

  @override
  Map<String, dynamic> changeset() {
    final changes = <String, dynamic>{};

    if (isNew && name != null || name != _name) {
      changes[nameKey] = name;
    }

    if (isNew && size != null || size != _size) {
      changes[sizeKey] = size;
    }

    if (isNew && sha256 != null || sha256 != _sha256) {
      changes[sha256Key] = sha256;
    }

    if (isNew && contentType != null || contentType != _contentType) {
      changes[contentTypeKey] = contentType;
    }

    if (isNew && encryptionKey != null || encryptionKey != _encryptionKey) {
      changes[encryptionKeyKey] =
          encryptionKey == null ? null : uint8ListToBase64(encryptionKey!);
    }

    // Sync the uploaded field so when syncing to other devices we know that this file has already been uploaded
    // We don't care to persist the default uploaded = 0 value on construction
    if (uploaded != _uploaded) {
      changes[uploadedKey] = uploaded;
    }

    if (isNew && sourceUserId != null || sourceUserId != _sourceUserId) {
      changes[sourceUserIdKey] = sourceUserId;
    }

    // local-only fields, don't sync these:
    // * downloaded
    // * not_found

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit() {
    _name = name;
    _size = size;
    _sha256 = sha256;
    _contentType = contentType;
    _encryptionKey = encryptionKey;
    _sourceUserId = sourceUserId;
    _uploaded = uploaded;
    baseCommit();
  }

  static File fromMap(Map<String, dynamic> map) {
    final file = File(
        name: map[nameKey],
        size: map[sizeKey],
        sha256: map[sha256Key],
        contentType: map[contentTypeKey],
        uploaded: (map[uploadedKey] ?? 0) == 1,
        downloaded: (map['downloaded'] ?? 0) == 1,
        notFound: (map['not_found'] ?? 0) == 1);

    if (map[encryptionKeyKey] != null) {
      file.encryptionKey = base64ToUint8List(map[encryptionKeyKey]);
    }

    file.sourceUserId = map[sourceUserIdKey];

    DBModel.mapBase(file, map);
    return file;
  }

  static List<File> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return File.fromMap(maps[i]);
    });
  }

  String getPath() {
    return join(config.dataPath, id);
  }

  io.File getFile() {
    return io.File(getPath());
  }

  String formatName() {
    return name ?? defaultFilename;
  }
}
