import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class Invitation {
  String userId;
  String invitationId;
  Uint8List userPublicKey;
  Uint8List signingPublicKey;
  Uint8List signingPrivateKey;

  Invitation(
    this.userId,
    this.invitationId,
    this.userPublicKey,
    this.signingPublicKey,
    this.signingPrivateKey,
  );

  Invitation.fromJson(Map<String, dynamic> map)
      : userId = map['user_id'],
        invitationId = map['invitation_id'],
        userPublicKey = base64ToUint8List(map['user_public_key']),
        signingPublicKey = base64ToUint8List(map['signing_public_key']),
        signingPrivateKey = base64ToUint8List(map['signing_private_key']);

  Map toJson() => {
        'user_id': userId,
        'invitation_id': invitationId,
        'user_public_key': uint8ListToBase64(userPublicKey),
        'signing_public_key': uint8ListToBase64(signingPublicKey),
        'signing_private_key': uint8ListToBase64(signingPrivateKey),
      };

  String serialize() {
    return jsonEncode(this);
  }

  static Invitation deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return Invitation.fromJson(decoded);
  }
}
