import 'package:stickerdocs_core/src/models/db/db_model.dart';

class SharedObject extends DBModel {
  static const String tableName = 'shared_object';
  static const String objectTypeKey = 'type';
  static const String objectIdKey = 'object_id';
  static const String trustedUserIdKey = 'trusted_user_id';

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
    commit(isNew: true);
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
  void commit({required bool isNew}) {
    _objectType = objectType;
    _objectId = objectId;
    _trustedUserId = trustedUserId;
    baseCommit(isNew: isNew);
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
