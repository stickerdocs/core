import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class RegisterVerifyResponse {
  final Uint8List requestSigningPrivateKey;

  RegisterVerifyResponse.fromJson(Map<String, dynamic> map)
      : requestSigningPrivateKey =
            base64ToUint8List(map['request_signing_private_key']);

  static RegisterVerifyResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return RegisterVerifyResponse.fromJson(decoded);
  }
}
