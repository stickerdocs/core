class UpgradeAvailable {
  final String version;
  final String? releaseNotes;
  final bool isCurrentVersionSupported;

  UpgradeAvailable({
    required this.version,
    required this.releaseNotes,
    required this.isCurrentVersionSupported,
  });
}
