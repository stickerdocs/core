import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class EncryptedInvitation {
  final Uint8List challengeSalt;
  final Uint8List challenge;

  EncryptedInvitation.fromJson(Map<String, dynamic> map)
      : challengeSalt = base64ToUint8List(map['challenge_salt']),
        challenge = base64ToUint8List(map['challenge']);

  static EncryptedInvitation deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    
    return EncryptedInvitation.fromJson(decoded);
  }
}
