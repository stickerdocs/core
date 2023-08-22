import 'package:stickerdocs_core/src/models/db/document.dart';
import 'package:stickerdocs_core/src/models/db/db_model.dart';

class FileDocument extends Document implements DBModel {
  static const String tableName = 'file_document';
  static const String fileIdKey = 'file_id';

  String fileId;

  // Shadow fields
  String? _fileId;

  FileDocument({
    required this.fileId,
  }) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || fileId != _fileId) {
      changes[fileIdKey] = fileId;
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _fileId = fileId;
    baseCommit(isNew: isNew);
  }

  static FileDocument fromMap(Map<String, dynamic> map) {
    final document = FileDocument(fileId: map[fileIdKey]);

    Document.mapBase(document, map);
    return document;
  }

  static List<FileDocument> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return FileDocument.fromMap(maps[i]);
    });
  }
}
