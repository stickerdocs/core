import 'package:flutter/widgets.dart';

import 'package:stickerdocs_core/models.dart';

class AppState {
  final documents = ValueNotifier<List<Document>>([]);
  final documentSearchController = TextEditingController();
  final stickers = ValueNotifier<List<Sticker>>([]);
  final stickerSearchController = TextEditingController();
  final sharedStickers = ValueNotifier<List<SharedSticker>>([]);
  final invitedUsers = ValueNotifier<List<InvitedUser>>([]);
  final invitationToAccept = ValueNotifier<InvitationToAccept?>(null);
  final trustedUsers = ValueNotifier<List<TrustedUser>>([]);
  final invitationInfo = ValueNotifier<InvitationInfo?>(null);
  final invitedSticker = ValueNotifier<Sticker?>(null);
  final accountDetails = ValueNotifier<AccountDetails?>(null);

  /// True if the app is synchronising
  final isSynchronising = ValueNotifier<bool>(false);

  final serviceMessage = ValueNotifier<String?>(null);
  final upgradeAvailable = ValueNotifier<UpgradeAvailable?>(null);

  // TODO: app should notify when this condition occurs, used for adding files
  final errorMessages = ValueNotifier<List<String>>([]);
}
