import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/utils.dart';

class TrustedUser extends DBModel {
  static const tableName = 'trusted_user';

  String userId;
  String name;
  String email;
  Uint8List publicKey;

  // Shadow fields
  String? _userId;
  String? _name;
  String? _email;
  Uint8List? _publicKey;

  TrustedUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.publicKey,
  }) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || userId != _userId) {
      changes['user_id'] = userId;
    }

    if (isNew || name != _name) {
      changes['name'] = name;
    }

    if (isNew || email != _email) {
      changes['email'] = email;
    }

    if (isNew || publicKey != _publicKey) {
      changes['public_key'] = uint8ListToBase64(publicKey);
    }

    populateCreatedAndUpdatedChanges(changes);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _userId = userId;
    _name = name;
    _email = email;
    _publicKey = publicKey;
    baseCommit(isNew: isNew);
  }

  static TrustedUser fromMap(Map<String, dynamic> map) {
    var trustedUser = TrustedUser(
      userId: map['user_id'],
      name: map['name'],
      email: map['email'],
      publicKey: base64ToUint8List(map['public_key']),
    );

    DBModel.mapBase(trustedUser, map);
    return trustedUser;
  }

  static List<TrustedUser> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return TrustedUser.fromMap(maps[i]);
    });
  }
}
