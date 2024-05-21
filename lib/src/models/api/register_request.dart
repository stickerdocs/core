import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/models/api/auth_request.dart';
import 'package:stickerdocs_core/src/models/encrypted_keys.dart';
import 'package:stickerdocs_core/src/utils.dart';

class RegisterRequest {
  final String name;
  final String email;
  final AuthRequest authRequest;
  final Uint8List dataPublicKey;
  final Uint8List signingPublicKey;
  final EncryptedKeys encryptedKeys;
  final String? token;

  const RegisterRequest({
    required this.name,
    required this.email,
    required this.authRequest,
    required this.dataPublicKey,
    required this.signingPublicKey,
    required this.encryptedKeys,
    required this.token,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = {
      'name': name,
      'email': email,
      'data_public_key': uint8ListToBase64(dataPublicKey),
      'signing_public_key': uint8ListToBase64(signingPublicKey),
    };

    map.addAll(authRequest.toJson());
    map.addAll(encryptedKeys.toJson());

    if (token != null) {
      map['token'] = token!;
    }

    return map;
  }
}
