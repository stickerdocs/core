import 'dart:convert';

import 'package:stickerdocs_core/src/utils.dart';

class AppVersion {
  final String version;
  final DateTime date;
  final String releaseNotes;

  AppVersion({
    required this.version,
    required this.date,
    required this.releaseNotes,
  });

  AppVersion.fromJson(Map<String, dynamic> map)
      : version = map['version'],
        date = fromIsoDateString(map['date'])!,
        releaseNotes = map['release_notes'];

  static AppVersion deserialize(String data, String packaging) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return AppVersion.fromJson(decoded[platformName][packaging]);
  }

  bool isNewer(String appVersion) {
    final myVersionParts = appVersion.split('.');
    final latestVersionParts = version.split('.');

    for (var index = 0; index < 3; index++) {
      if (int.parse(latestVersionParts[index]) >
          int.parse(myVersionParts[index])) {
        return true;
      }
    }

    return false;
  }
}
