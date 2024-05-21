import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/models/api/auth_request.dart';
import 'package:stickerdocs_core/src/utils.dart';

class ChangeEmailVerifyRequest {
  final Uint8List challengeResponse;
  final String email;
  final AuthRequest authRequest;

  ChangeEmailVerifyRequest({
    required this.challengeResponse,
    required this.email,
    required this.authRequest,
  });

  Map<String, dynamic> toJson() {
    Map<String, dynamic> map = {
      'challenge_response': uint8ListToBase64(challengeResponse),
      'email': email,
    };

    map.addAll(authRequest.toJson());

    return map;
  }
}
