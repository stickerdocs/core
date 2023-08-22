import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class InvitationResponse {
  final String userId;
  final String userName;
  final String userEmail;
  final Uint8List publicKey;
  final Uint8List signature;

  InvitationResponse({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.publicKey,
    required this.signature,
  });

  InvitationResponse.fromJson(Map<String, dynamic> map)
      : userId = map['user_id'],
        userName = map['user_name'],
        userEmail = map['user_email'],
        publicKey = base64ToUint8List(map['public_key']),
        signature = base64ToUint8List(map['signature']);

  static InvitationResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return InvitationResponse.fromJson(decoded);
  }
}
