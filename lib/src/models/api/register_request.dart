import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class RegisterRequest {
  final String name;
  final String email;
  final Uint8List authPublicKey;
  final Uint8List authKey;
  final Uint8List dataPublicKey;
  final Uint8List encryptedDataPrivateKey;
  final Uint8List signingPublicKey;
  final Uint8List encryptedSigningPrivateKey;
  final Uint8List keySalt;
  final String? token;

  const RegisterRequest(
      {required this.name,
      required this.email,
      required this.authPublicKey,
      required this.authKey,
      required this.dataPublicKey,
      required this.encryptedDataPrivateKey,
      required this.signingPublicKey,
      required this.encryptedSigningPrivateKey,
      required this.keySalt,
      required this.token});

  Map<String, dynamic> toJson() {
    final map = {
      'name': name,
      'email': email,
      'auth_public_key': uint8ListToBase64(authPublicKey),
      'auth_key': uint8ListToBase64(authKey),
      'data_public_key': uint8ListToBase64(dataPublicKey),
      'encrypted_data_private_key': uint8ListToBase64(encryptedDataPrivateKey),
      'signing_public_key': uint8ListToBase64(signingPublicKey),
      'encrypted_signing_private_key':
          uint8ListToBase64(encryptedSigningPrivateKey),
      'key_salt': uint8ListToBase64(keySalt)
    };

    if (token != null) {
      map['token'] = token!;
    }

    return map;
  }
}
