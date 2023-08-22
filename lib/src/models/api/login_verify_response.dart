import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class LoginVerifyResponse {
  final String userId;
  final Uint8List dataPublicKey;
  final Uint8List encryptedDataPrivateKey;
  final Uint8List signingPublicKey;
  final Uint8List encryptedSigningPrivateKey;
  final Uint8List keySalt;
  final Uint8List requestSigningPrivateKey;

  const LoginVerifyResponse({
    required this.userId,
    required this.dataPublicKey,
    required this.encryptedDataPrivateKey,
    required this.signingPublicKey,
    required this.encryptedSigningPrivateKey,
    required this.keySalt,
    required this.requestSigningPrivateKey,
  });

  LoginVerifyResponse.fromJson(Map<String, dynamic> map)
      : userId = map['user_id'],
        dataPublicKey = base64ToUint8List(map['data_public_key']),
        encryptedDataPrivateKey =
            base64ToUint8List(map['encrypted_data_private_key']),
        signingPublicKey = base64ToUint8List(map['signing_public_key']),
        encryptedSigningPrivateKey =
            base64ToUint8List(map['encrypted_signing_private_key']),
        keySalt = base64ToUint8List(map['key_salt']),
        requestSigningPrivateKey =
            base64ToUint8List(map['request_signing_private_key']);

  static LoginVerifyResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return LoginVerifyResponse.fromJson(decoded);
  }
}
