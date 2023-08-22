import 'dart:convert';
import 'dart:typed_data';

import 'package:stickerdocs_core/src/utils.dart';

class EventFile {
  String firstTimestamp;
  String fileId;
  Uint8List fileEncryptedKey;
  String? sourceUserId;
  List<String> fileIdsToShare = [];
  List<String> fileIdsToUnshare = [];

  EventFile({
    required this.firstTimestamp,
    required this.fileId,
    required this.fileEncryptedKey,
  });

  Map<String, dynamic> toJson() => {
        'first_timestamp': firstTimestamp,
        'file_id': fileId,
        'encrypted_key': uint8ListToBase64(fileEncryptedKey),
        'file_ids_to_share': fileIdsToShare,
        'file_ids_to_unshare': fileIdsToUnshare,
      };

  EventFile.fromJson(Map<String, dynamic> map)
      : firstTimestamp = map['first_timestamp'],
        fileId = map['file_id'],
        fileEncryptedKey = base64ToUint8List(map['encrypted_key']);

  static List<EventFile> deserialize(String data) {
    List<EventFile> events = [];

    for (final item in jsonDecode(data)) {
      events.add(EventFile.fromJson(item));
    }

    return events;
  }
}
