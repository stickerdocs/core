import 'package:stickerdocs_core/src/models/api/invitation_response.dart';
import 'package:stickerdocs_core/src/models/db/invited_user.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';

class InvitationToAccept {
  InvitedUser invitedUser;
  InvitationResponse response;
  Sticker sticker;

  InvitationToAccept(
    this.invitedUser,
    this.response,
    this.sticker,
  );
}
