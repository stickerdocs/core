import 'package:stickerdocs_core/src/utils.dart';

const dbModelDeleted = 'deleted';

abstract class DBModel {
  static const createdKey = 'created';
  static const updatedKey = 'updated';

  /// The corresponding backing DB table name
  late String table;

  /// The id of this object
  String id = newUuid();

  /// When the object was created
  DateTime created = isoDateNow();

  /// When the object was created (shadow field)
  late DateTime _created;

  /// When the object was last updated
  DateTime updated = isoDateNow();

  /// When the object was last updated (shadow field)
  late DateTime _updated;

  /// True if the object is newly created
  bool isNew = true;

  /// Get a list of changes made to the model
  Map<String, dynamic> changeset();

  void populateCreatedAndUpdatedChanges(Map<String, dynamic> changes,
      {bool updatable = true}) {
    if (isNew || created != _created) {
      changes[createdKey] = created;
    }

    if (!updatable) {
      return;
    }

    if (isNew || updated != _updated) {
      changes[updatedKey] = updated;
    } else if (changes.isNotEmpty) {
      changes[updatedKey] = isoDateNow();
    }
  }

  /// Commit the changes made
  void commit();

  void baseCommit() {
    _created = created;
    _updated = updated;
  }

  static void mapBase(DBModel object, Map<String, dynamic> map) {
    object.id = map['${object.table}_id'];
    object.created = fromIsoDateString(map[createdKey])!;

    if (map.containsKey(updatedKey)) {
      object.updated = fromIsoDateString(map[updatedKey])!;
    }

    // Object has been loaded from the DB so it is not new
    object.isNew = false;

    object.commit();
  }
}
