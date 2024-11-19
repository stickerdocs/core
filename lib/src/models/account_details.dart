class AccountDetails {
  final String email;
  final String? name;
  final bool? subscriptionActive;
  final bool? canUpload;
  final int? storageQuotaBytes;
  final int? storageBytesUsed;
  final String? storageMethod;
  final int? invitationQuota;
  final int? invitationsUsed;

  AccountDetails({
    required this.email,
    this.name,
    this.subscriptionActive,
    this.canUpload,
    this.storageQuotaBytes,
    this.storageBytesUsed,
    this.storageMethod,
    this.invitationQuota,
    this.invitationsUsed,
  });
}
