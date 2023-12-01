import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:sodium/sodium.dart';

import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/services/crypto_engine.dart';

import 'mock.mocks.dart';

class FakeConfigService extends Fake implements ConfigService {
  String? dataPrivateKeyValue;
  String? dataPublicKeyValue;

  @override
  Future<void> setDataPrivateKey(String? value) async {
    dataPrivateKeyValue = value;
  }

  @override
  Future<String?> get dataPrivateKey async {
    return dataPrivateKeyValue;
  }

  @override
  Future<String?> get dataPublicKey async {
    return dataPublicKeyValue;
  }

  @override
  Future<void> setDataPublicKey(String? value) async {
    dataPublicKeyValue = value;
  }
}

void main() {
  late CryptoService service;
  late CryptoEngine mockEngine;

  Uint8List stickerDocsPublicKey = Uint8List.fromList([190, 23]);
  Uint8List reportHarmPublicKey = Uint8List.fromList([104, 144]);
  Uint8List publicKey = Uint8List.fromList([228, 191]);
  SecureKey secureKey = MockSecureKey();
  Uint8List secureKeyBytes = Uint8List.fromList([78, 115]);
  KeyPair keyPair = KeyPair(publicKey: publicKey, secretKey: secureKey);
  Uint8List nonce = Uint8List.fromList([241, 182]);
  Uint8List boxNonce = Uint8List.fromList([146, 9]);

  setUp(() async {
    GetIt.I.registerSingleton<ConfigService>(FakeConfigService());
    GetIt.I.registerSingleton<CryptoEngine>(MockCryptoEngine());
    GetIt.I.registerSingleton<CryptoService>(
        CryptoService(stickerDocsPublicKey, reportHarmPublicKey));

    service = GetIt.I.get<CryptoService>();
    mockEngine = GetIt.I.get<CryptoEngine>();

    when(secureKey.extractBytes()).thenReturn(secureKeyBytes);
    when(mockEngine.generateBoxKeyPair()).thenReturn(keyPair);
    when(mockEngine.generateBoxNonce()).thenReturn(boxNonce);
    when(mockEngine.generateSecretBoxSecureKey()).thenReturn(secureKey);
    when(mockEngine.generateSecretBoxNonce()).thenReturn(nonce);
    when(mockEngine.boxNonceBytes).thenReturn(2);
  });

  tearDown(() {
    GetIt.I.reset();
  });

  test('Decrypt should return input to Encrypt', () async {
    final message = Uint8List.fromList([112, 37]);
    final encryptedData = Uint8List.fromList([20, 255]);

    when(mockEngine.secretBoxEncrypt(secureKeyBytes, nonce, secureKey))
        .thenReturn(Uint8List.fromList([12, 97]));

    when(mockEngine.boxEncrypt(message, boxNonce, publicKey, secureKey))
        .thenReturn(encryptedData);

    final encrypted = await service.encryptForMe(message);

    expect(encrypted, boxNonce + encryptedData);

    when(mockEngine.boxDecrypt(encryptedData, boxNonce, publicKey, secureKey))
        .thenReturn(message);

    final decrypted = await service.decryptFromMe(encrypted!);

    expect(decrypted, message);
  });
}
