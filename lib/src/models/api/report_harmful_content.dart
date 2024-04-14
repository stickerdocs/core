import 'dart:typed_data';

import 'package:stickerdocs_core/src/utils.dart';

class ReportHarmfulContent {
  String sharedByUserId;
  String fileId;
  String fileName;
  String reason;
  String md5;
  String sha256;
  String sha512;
  Uint8List thisFileReEncryptedKey;
  Uint8List sharedFileReEncryptedKey;
  String? signature;

  ReportHarmfulContent({
    required this.sharedByUserId,
    required this.fileId,
    required this.fileName,
    required this.reason,
    required this.md5,
    required this.sha256,
    required this.sha512,
    required this.thisFileReEncryptedKey,
    required this.sharedFileReEncryptedKey,
  });

  Map<String, dynamic> toJson() {
    final map = {
      'shared_by_user_id': sharedByUserId,
      'file_id': fileId,
      'file_name': fileName,
      'reason': reason,
      'md5': md5,
      'sha256': sha256,
      'sha512': sha512,
      'this_file_re_encrypted_key': uint8ListToBase64(thisFileReEncryptedKey),
      'shared_file_re_encrypted_key':
          uint8ListToBase64(sharedFileReEncryptedKey),
    };

    if (signature != null) {
      map['signature'] = signature!;
    }

    return map;
  }
}
