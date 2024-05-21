import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/utils.dart';

class EncryptedKeys {
  final Uint8List encryptedDataPrivateKey;
  final Uint8List encryptedSigningPrivateKey;
  final Uint8List keySalt;

  EncryptedKeys({
    required this.encryptedDataPrivateKey,
    required this.encryptedSigningPrivateKey,
    required this.keySalt,
  });

  Map<String, dynamic> toJson() => {
        'encrypted_data_private_key':
            uint8ListToBase64(encryptedDataPrivateKey),
        'encrypted_signing_private_key':
            uint8ListToBase64(encryptedSigningPrivateKey),
        'key_salt': uint8ListToBase64(keySalt)
      };
}
