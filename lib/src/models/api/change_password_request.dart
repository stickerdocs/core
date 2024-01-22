import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class ChangePasswordRequest {
  final Uint8List authPublicKey;
  final Uint8List authKey;
  Uint8List? challengeResponse;

   ChangePasswordRequest(
      {required this.authPublicKey, required this.authKey});

  Map<String, dynamic> toJson() => {
    // we reuse this public key for the challenge response for verify
        'auth_public_key': uint8ListToBase64(authPublicKey),
        'auth_key': uint8ListToBase64(authKey),
      };
}
