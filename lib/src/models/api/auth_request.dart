import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class AuthRequest {
  final Uint8List authPublicKey;
  final Uint8List authKey;

  const AuthRequest({
    required this.authPublicKey,
    required this.authKey,
  });

  Map<String, dynamic> toJson() => {
        'auth_public_key': uint8ListToBase64(authPublicKey),
        'auth_key': uint8ListToBase64(authKey)
      };
}
