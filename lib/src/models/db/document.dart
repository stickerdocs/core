import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/utils.dart';

abstract class Document extends DBModel {
  static const titleKey = 'title';

  /// The title of the document
  String? title;

  /// The title of the document (shadow field)
  String? _title;

  @override
  void populateCreatedAndUpdatedChanges(Map<String, dynamic> changes,
      {bool updatable = true}) {
    if (isNew || title != _title) {
      changes[titleKey] = title;
    }

    super.populateCreatedAndUpdatedChanges(changes, updatable: updatable);
  }

  @override
  void baseCommit() {
    _title = title;
    super.baseCommit();
  }

  static void mapBase(Document document, Map<String, dynamic> map) {
    document.title = map[titleKey];
    DBModel.mapBase(document, map);
  }

  String formatTitle() {
    return title ?? defaultFilename;
  }
}
