import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class LoginRequest {
  final String email;
  final Uint8List authPublicKey;
  final Uint8List authKey;

  const LoginRequest({
    required this.email,
    required this.authPublicKey,
    required this.authKey,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'auth_public_key': uint8ListToBase64(authPublicKey),
        'auth_key': uint8ListToBase64(authKey)
      };
}
