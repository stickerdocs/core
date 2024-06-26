import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/models/api/auth_request.dart';
import 'package:stickerdocs_core/src/models/encrypted_keys.dart';
import 'package:stickerdocs_core/src/utils.dart';

class ChangePasswordVerifyRequest {
  final Uint8List challengeResponse;
  final AuthRequest authRequest;
  final EncryptedKeys encryptedKeys;

  ChangePasswordVerifyRequest({
    required this.challengeResponse,
    required this.authRequest,
    required this.encryptedKeys,
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {
      'challenge_response': uint8ListToBase64(challengeResponse),
    };

    map.addAll(authRequest.toJson());
    map.addAll(encryptedKeys.toJson());
    
    return map;
  }
}
