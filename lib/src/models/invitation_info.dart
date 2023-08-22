import 'dart:convert';
import 'dart:typed_data';

import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/utils.dart';

class InvitationInfo {
  final String senderName;
  final String senderEmail;
  final String stickerId;
  final String stickerName;
  final String stickerStyle;
  final Uint8List stickerSvg;

  InvitationInfo({
    required this.senderName,
    required this.senderEmail,
    required this.stickerId,
    required this.stickerName,
    required this.stickerStyle,
    required this.stickerSvg,
  });

  InvitationInfo.fromJson(Map<String, dynamic> map)
      : senderName = map['sender_name'],
        senderEmail = map['sender_email'],
        stickerId = map['sticker_id'],
        stickerName = map['sticker_name'],
        stickerStyle = map['sticker_style'],
        stickerSvg = base64ToUint8List(map['sticker_svg']);

  static InvitationInfo deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return InvitationInfo.fromJson(decoded);
  }

  Sticker toSticker() {
    final sticker = Sticker(name: stickerName);
    sticker.id = stickerId;
    sticker.style = stickerStyle;
    sticker.svg = stickerSvg;
    return sticker;
  }
}
