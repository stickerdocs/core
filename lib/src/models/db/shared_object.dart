import 'package:stickerdocs_core/src/models/db/db_model.dart';

class SharedObject extends DBModel {
  static const tableName = 'shared_object';
  static const objectTypeKey = 'type';
  static const objectIdKey = 'object_id';
  static const trustedUserIdKey = 'trusted_user_id';

  String objectType;
  String objectId;
  String trustedUserId;

  // Shadow fields
  String? _objectType;
  String? _objectId;
  String? _trustedUserId;

  SharedObject({
    required this.objectType,
    required this.objectId,
    required this.trustedUserId,
  }) {
    table = tableName;
    commit();
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || objectType != _objectType) {
      changes[objectTypeKey] = objectType;
    }

    if (isNew || objectId != _objectId) {
      changes[objectIdKey] = objectId;
    }

    if (isNew || trustedUserId != _trustedUserId) {
      changes[trustedUserIdKey] = trustedUserId;
    }

    populateCreatedAndUpdatedChanges(changes, updatable: false);
    return changes;
  }

  @override
  void commit() {
    _objectType = objectType;
    _objectId = objectId;
    _trustedUserId = trustedUserId;
    baseCommit();
  }

  static SharedObject fromMap(Map<String, dynamic> map) {
    final document = SharedObject(
      objectType: map[objectTypeKey],
      objectId: map[objectIdKey],
      trustedUserId: map[trustedUserIdKey],
    );

    DBModel.mapBase(document, map);
    return document;
  }

  static List<SharedObject> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return SharedObject.fromMap(maps[i]);
    });
  }
}
