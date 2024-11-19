import 'dart:convert';

import 'package:stickerdocs_core/src/models/account_details.dart';

class AccountDetailsResponse {
  final String name;
  final String email;
  final bool subscriptionActive;
  final bool canUpload;
  final int storageQuotaBytes;
  final int storageBytesUsed;
  final String storageMethod;
  final int invitationQuota;
  final int invitationsUsed;

  AccountDetailsResponse({
    required this.name,
    required this.email,
    required this.subscriptionActive,
    required this.canUpload,
    required this.storageQuotaBytes,
    required this.storageBytesUsed,
    required this.storageMethod,
    required this.invitationQuota,
    required this.invitationsUsed,
  });

  AccountDetailsResponse.fromJson(Map<String, dynamic> map)
      : name = map['name'],
        email = map['email'],
        subscriptionActive = map['subscription_active'],
        canUpload = map['can_upload'],
        storageQuotaBytes = map['storage_quota_bytes'],
        storageBytesUsed = map['storage_bytes_used'],
        storageMethod = map['storage_method'],
        invitationQuota = map['invitation_quota'],
        invitationsUsed = map['invitations_used'];

  static AccountDetailsResponse deserialize(String data) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return AccountDetailsResponse.fromJson(decoded);
  }

  AccountDetails toAccountDetails() {
    return AccountDetails(
      name: name,
      email: email,
      subscriptionActive: subscriptionActive,
      canUpload: canUpload,
      storageQuotaBytes: storageQuotaBytes,
      storageBytesUsed: storageBytesUsed,
      storageMethod: storageMethod,
      invitationQuota: invitationQuota,
      invitationsUsed: invitationsUsed,
    );
  }
}
