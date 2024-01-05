import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class ChangePasswordRequest {
  final Uint8List authPublicKey;
  final Uint8List oldAuthKey;
  final Uint8List newAuthKey;

  const ChangePasswordRequest({
    required this.authPublicKey,
    required this.oldAuthKey,
    required this.newAuthKey
  });

  Map<String, dynamic> toJson() => {
        'auth_public_key': uint8ListToBase64(authPublicKey),
        'old_auth_key': uint8ListToBase64(oldAuthKey),
        'new_auth_key': uint8ListToBase64(newAuthKey)
      };
}
