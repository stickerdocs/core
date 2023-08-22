import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/utils.dart';

class InvitationRequest {
  final DateTime created = isoDateNow();
  final String invitationId;
  final String recipientName;
  final String recipientEmail;
  final Sticker sticker;
  final Uint8List stickerImage;
  final Uint8List signingPublicKey;
  final Uint8List challengeSalt;
  final Uint8List challenge;

  InvitationRequest({
    required this.invitationId,
    required this.recipientName,
    required this.recipientEmail,
    required this.sticker,
    required this.stickerImage,
    required this.signingPublicKey,
    required this.challengeSalt,
    required this.challenge,
  });

  Map<String, dynamic> toJson() => {
        'created': isoDateToString(created),
        'invitation_id': invitationId,
        'recipient_name': recipientName,
        'recipient_email': recipientEmail,
        'sticker_id': sticker.id,
        'sticker_name': sticker.name,
        'sticker_style': sticker.style,
        'sticker_svg': uint8ListToBase64(sticker.svg!),
        'sticker_image': uint8ListToBase64(stickerImage),
        'signing_public_key': uint8ListToBase64(signingPublicKey),
        'challenge_salt': uint8ListToBase64(challengeSalt),
        'challenge': uint8ListToBase64(challenge),
      };
}
