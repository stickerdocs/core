import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class DeleteAccountVerifyRequest {
  final Uint8List challengeResponse;

  DeleteAccountVerifyRequest({required this.challengeResponse});

  Map<String, dynamic> toJson() =>
      {'challenge_response': uint8ListToBase64(challengeResponse)};
}
