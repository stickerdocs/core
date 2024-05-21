import 'dart:async';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs.dart';

import 'package:stickerdocs_core/src/utils.dart';

late final Sodium _sodium;

Future<void> initCryptoEngine() async {
  _sodium = await SodiumInit.init();
}

class CryptoEngine {
  SecureKey loadSecureKey(Uint8List data) {
    return SecureKey.fromList(_sodium, data);
  }

  Uint8List generateSaltForPasswordHashing() {
    return _sodium.randombytes.buf(_sodium.crypto.pwhash.saltBytes);
  }

  // https://libsodium.gitbook.io/doc/password_hashing/default_phf#example-1-key-derivation
  SecureKey passwordHash(Uint8List salt, Int8List password) {
    return _sodium.crypto.pwhash.call(
        outLen: _sodium.crypto.secretBox.keyBytes,
        password: password,
        salt: salt,
        opsLimit: _sodium.crypto.pwhash.opsLimitInteractive,
        memLimit: _sodium.crypto.pwhash.memLimitInteractive);
  }

  int get deterministicSeedBytes {
    return _sodium.randombytes.seedBytes;
  }

  Uint8List generateDeterministicRandom(Uint8List seed) {
    return _sodium.randombytes
        .bufDeterministic(_sodium.crypto.pwhash.saltBytes, seed);
  }

  SecureKey generateSecretBoxSecureKey() {
    return _sodium.crypto.secretBox.keygen();
  }

  int get secretBoxNonceBytes {
    return _sodium.crypto.secretBox.nonceBytes;
  }

  Uint8List generateSecretBoxNonce() {
    return _sodium.randombytes.buf(secretBoxNonceBytes);
  }

  Uint8List? secretBoxEncrypt(
      Uint8List message, Uint8List nonce, SecureKey key) {
    try {
      return _sodium.crypto.secretBox
          .easy(message: message, nonce: nonce, key: key);
    } on SodiumException catch (exception) {
      logger.e(exception);
      return null;
    }
  }

  Uint8List? secretBoxDecrypt(
      Uint8List cipherText, Uint8List nonce, SecureKey key) {
    try {
      return _sodium.crypto.secretBox
          .openEasy(cipherText: cipherText, nonce: nonce, key: key);
    } on SodiumException catch (exception) {
      logger.e(exception);
      return null;
    }
  }

  KeyPair generateBoxKeyPair() {
    return _sodium.crypto.box.keyPair();
  }

  int get boxNonceBytes {
    return _sodium.crypto.box.nonceBytes;
  }

  Uint8List generateBoxNonce() {
    return _sodium.randombytes.buf(boxNonceBytes);
  }

  Uint8List? boxEncrypt(Uint8List message, Uint8List nonce, Uint8List publicKey,
      SecureKey secretKey) {
    try {
      return _sodium.crypto.box.easy(
          message: message,
          nonce: nonce,
          publicKey: publicKey,
          secretKey: secretKey);
    } on SodiumException catch (exception) {
      logger.e(exception);
      return null;
    }
  }

  Uint8List? boxDecrypt(Uint8List cipherText, Uint8List nonce,
      Uint8List publicKey, SecureKey secretKey) {
    try {
      return _sodium.crypto.box.openEasy(
          cipherText: cipherText,
          nonce: nonce,
          publicKey: publicKey,
          secretKey: secretKey);
    } on SodiumException catch (exception) {
      logger.e(exception);
      return null;
    }
  }

  KeyPair generateSigningKeyPair() {
    return _sodium.crypto.sign.keyPair();
  }

  Uint8List sign(Uint8List message, SecureKey secretKey) {
    return _sodium.crypto.sign.detached(message: message, secretKey: secretKey);
  }

  bool verifySignature(
      Uint8List message, Uint8List signature, Uint8List publicKey) {
    return _sodium.crypto.sign.verifyDetached(
        message: message, signature: signature, publicKey: publicKey);
  }
}
