import 'package:flutter/widgets.dart';

import 'package:stickerdocs_core/models.dart';

class AppState {
  final sharedStickers = ValueNotifier<List<SharedSticker>>([]);
  final documents = ValueNotifier<List<Document>>([]);
  final stickers = ValueNotifier<List<Sticker>>([]);
  final invitedUsers = ValueNotifier<List<InvitedUser>>([]);
  final invitationToAccept = ValueNotifier<InvitationToAccept?>(null);
  final trustedUsers = ValueNotifier<List<TrustedUser>>([]);
  final invitationInfo = ValueNotifier<InvitationInfo?>(null);
  final invitedSticker = ValueNotifier<Sticker?>(null);
  final accountDetails = ValueNotifier<AccountDetails?>(null);

  /// True if the app is synchrnonising
  final synchronising = ValueNotifier<bool>(false);

  AppState() {
    // When the email is updated, also update whether we are logged in or not
    // accountDetails.addListener(() {
    //   loggedIn.value = !accountDetails.isNull;
    // });
  }
}
