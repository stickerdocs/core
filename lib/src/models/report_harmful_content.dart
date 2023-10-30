import 'dart:typed_data';

import 'package:stickerdocs_core/src/utils.dart';

class ReportHamrfulContent {
  String sharedByUserId;
  String fileId;
  Uint8List encryptedHarmfulContent;
  Uint8List signedHarmfulContent;
  String sha256;
  String md5;
  String sharedFileEncryptedPassword;

  ReportHamrfulContent({
    required this.sharedByUserId,
    required this.fileId,
    required this.encryptedHarmfulContent,
    required this.signedHarmfulContent,
    required this.sha256,
    required this.md5,
    required this.sharedFileEncryptedPassword,
  });

  Map<String, dynamic> toJson() => {
        'shared_by_user_id': sharedByUserId,
        'file_id': fileId,
        'encrypted_harmful_content': uint8ListToBase64(encryptedHarmfulContent),
        'signed_harmful_content': uint8ListToBase64(signedHarmfulContent),
        'sha256': sha256,
        'md5': md5,
        'shared_file_encrypted_password': sharedFileEncryptedPassword,
      };
}