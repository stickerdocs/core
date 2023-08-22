import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/utils.dart';

class InvitedUser extends DBModel {
  static const String tableName = 'invitation';

  String stickerId;
  String name;
  String email;
  Uint8List? signingPublicKey;
  Uint8List? signingPrivateKey;

  // Shadow fields
  String? _stickerId;
  String? _name;
  String? _email;
  Uint8List? _signingPublicKey;
  Uint8List? _signingPrivateKey;

  InvitedUser({
    required this.stickerId,
    required this.name,
    required this.email,
  }) {
    table = tableName;
    commit(isNew: true);
  }

  @override
  Map<String, dynamic> changeset() {
    var changes = <String, dynamic>{};

    if (isNew || stickerId != _stickerId) {
      changes['sticker_id'] = stickerId;
    }

    if (isNew || name != _name) {
      changes['name'] = name;
    }

    if (isNew || email != _email) {
      changes['email'] = email;
    }

    if (isNew && signingPublicKey != null ||
        signingPublicKey != _signingPublicKey) {
      changes['signing_public_key'] = uint8ListToBase64(signingPublicKey!);
    }

    if (isNew && signingPrivateKey != null ||
        signingPrivateKey != _signingPrivateKey) {
      changes['signing_private_key'] = uint8ListToBase64(signingPrivateKey!);
    }

    populateCreatedAndUpdatedChanges(changes, updatable: false);
    return changes;
  }

  @override
  void commit({required bool isNew}) {
    _stickerId = stickerId;
    _name = name;
    _email = email;
    _signingPublicKey = signingPublicKey;
    _signingPrivateKey = signingPrivateKey;
    baseCommit(isNew: isNew);
  }

  static InvitedUser fromMap(Map<String, dynamic> map) {
    var invitation = InvitedUser(
      stickerId: map['sticker_id'],
      name: map['name'],
      email: map['email'],
    );

    if (map['signing_public_key'] != null) {
      invitation.signingPublicKey =
          base64ToUint8List(map['signing_public_key']);
    }

    if (map['signing_private_key'] != null) {
      invitation.signingPrivateKey =
          base64ToUint8List(map['signing_private_key']);
    }

    DBModel.mapBase(invitation, map);
    return invitation;
  }

  static List<InvitedUser> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return InvitedUser.fromMap(maps[i]);
    });
  }
}
