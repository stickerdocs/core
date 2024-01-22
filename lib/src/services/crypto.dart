import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:sodium/sodium.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stickerdocs_core/src/models/api/challenge_request.dart';
import 'package:stickerdocs_core/src/models/api/change_password_request.dart';

import 'package:stickerdocs_core/src/models/api/invitation_response.dart';
import 'package:stickerdocs_core/src/models/api/invitation_request.dart';
import 'package:stickerdocs_core/src/models/db/invited_user.dart';
import 'package:stickerdocs_core/src/models/invitation.dart';
import 'package:stickerdocs_core/src/models/api/register_request.dart';
import 'package:stickerdocs_core/src/models/register_verify_response.dart';
import 'package:stickerdocs_core/src/models/api/login_request.dart';
import 'package:stickerdocs_core/src/models/api/login_verify_response.dart';
import 'package:stickerdocs_core/src/models/api/encrypted_invitation.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/services/crypto_engine.dart';
import 'package:stickerdocs_core/src/utils.dart';
import 'package:stickerdocs_core/src/main.dart';

const int fileHashChunkSize = 1024;

class SaltAndKey {
  Uint8List salt;
  SecureKey key;
  SaltAndKey(this.salt, this.key);
}

class CryptoService {
  Uint8List stickerDocsPublicKey;
  Uint8List reportHarmPublicKey;
  final CryptoEngine _engine = GetIt.I.get<CryptoEngine>();
  String? _ephemeralPassword;
  KeyPair? _ephemeralAccountKeyPairValue;
  KeyPair? _dataKeyPairValue;
  KeyPair? _signingKeyPairValue;
  SecureKey? _apiRequestSigningPrivateKey;

  SecureKey? _configKeyInstance;

  CryptoService(this.stickerDocsPublicKey, this.reportHarmPublicKey);

  Future<SecureKey> get _configKey async {
    if (_configKeyInstance == null) {
      await _initConfigKey();
    }

    return _configKeyInstance!;
  }

  Future<void> _initConfigKey() async {
    // Bypass FlutterSecureStorage when performing unit tests
    if (kDebugMode) {
      if (io.Platform.environment.containsKey('FLUTTER_TEST')) {
        _configKeyInstance = _engine.generateSecretBoxSecureKey();
        return;
      }
    }

    const storage = FlutterSecureStorage();
    const storageKey = 'config_key';

    var keyString = await storage.read(key: storageKey);

    if (keyString == null) {
      _configKeyInstance = _engine.generateSecretBoxSecureKey();
      await storage.write(
          key: storageKey,
          value: uint8ListToBase64(_configKeyInstance!.extractBytes()));
    } else {
      _configKeyInstance = _engine.loadSecureKey(base64ToUint8List(keyString));
    }
  }

  // We will re-use this ephemeral key for the duration of the app lifecycle.
  // We use this to keep credentials secure in case of HTTPS interception hardware on the network.
  // The login process stores this public key for decrypting the verification challenge response
  //
  // Public + private key both 32 bytes
  KeyPair get _ephemeralAccountKeyPair {
    _ephemeralAccountKeyPairValue ??= _engine.generateBoxKeyPair();
    return _ephemeralAccountKeyPairValue!;
  }

  // generate a data key pair if required and persist in the config
  // Public + private key both 32 bytes
  Future<KeyPair> get _dataKeyPair async {
    // Do we already have this?
    if (_dataKeyPairValue != null) {
      return _dataKeyPairValue!;
    }

    final dataPrivateKey = await config.dataPrivateKey;
    final dataPublicKey = await config.dataPublicKey;

    // Try to load from config
    if (dataPrivateKey != null && dataPublicKey != null) {
      var privateKey = await _decryptConfigSetting(dataPrivateKey);
      var publicKey = base64ToUint8List(dataPublicKey);
      var secretKey = _engine.loadSecureKey(privateKey!);
      _dataKeyPairValue = KeyPair(secretKey: secretKey, publicKey: publicKey);
    } else {
      // Generate a new key pair
      _dataKeyPairValue = _engine.generateBoxKeyPair();

      // Persist in DB
      await _setDataKeyPair(_dataKeyPairValue!);
    }

    return _dataKeyPairValue!;
  }

  Future<void> _setDataKeyPair(KeyPair keyPair) async {
    _dataKeyPairValue = keyPair;

    final encryptedSecretKey =
        await _encryptConfigSetting(keyPair.secretKey.extractBytes());

    await config.setDataPublicKey(uint8ListToBase64(keyPair.publicKey));
    await config.setDataPrivateKey(encryptedSecretKey);
  }

  // Public key = 32 bytes, private key = 64 bytes
  Future<KeyPair> get _signingKeyPair async {
    // Do we already have this?
    if (_signingKeyPairValue != null) {
      return _signingKeyPairValue!;
    }

    final signingPrivateKey = await config.signingPrivateKey;
    final signingPublicKey = await config.signingPublicKey;

    // Try to load from config
    if (signingPrivateKey != null && signingPublicKey != null) {
      var privateKey = await _decryptConfigSetting(signingPrivateKey);
      var publicKey = base64ToUint8List(signingPublicKey);
      var secretKey = _engine.loadSecureKey(privateKey!);
      _signingKeyPairValue =
          KeyPair(secretKey: secretKey, publicKey: publicKey);
    } else {
      // Generate a new key pair
      _signingKeyPairValue = _engine.generateSigningKeyPair();

      // Persist in DB
      await _setSigningKeyPair(_signingKeyPairValue!);
    }

    return _signingKeyPairValue!;
  }

  Future<void> _setSigningKeyPair(KeyPair keyPair) async {
    _signingKeyPairValue = keyPair;

    final encryptedSecretKey =
        await _encryptConfigSetting(keyPair.secretKey.extractBytes());

    await config.setSigningPublicKey(uint8ListToBase64(keyPair.publicKey));
    await config.setSigningPrivateKey(encryptedSecretKey);
  }

  static String md5(List<int> message) {
    return hash.md5.convert(message).toString();
  }

  static String sha256(List<int> message) {
    return hash.sha256.convert(message).toString();
  }

  static Future<String> sha256File(io.File file) async {
    final output = AccumulatorSink<hash.Digest>();
    final input = hash.sha256.startChunkedConversion(output);

    final fileHandle = await file.open(mode: io.FileMode.read);

    Uint8List data;

    do {
      data = await fileHandle.read(fileHashChunkSize);
      input.add(data);
    } while (data.length == fileHashChunkSize);

    input.close();
    await fileHandle.close();

    return output.events.single.toString();
  }

  SaltAndKey _deriveKey(String password) {
    // 16 bytes for salt
    final salt = _engine.generateSaltForPasswordHashing();

    return SaltAndKey(salt, _engine.passwordHash(salt, password));
  }

  SecureKey _deriveDeterministicKey(String email, String password) {
    var emailSeed = email;

    // Build up a repeating string containing the email to get to a desired seed length
    while (emailSeed.toCharArray().length < _engine.deterministicSeedBytes) {
      emailSeed += email;
    }

    // We want 32 bytes of this repeating email string
    final seed = Uint8List.fromList(emailSeed
        .toCharArray()
        .getRange(0, _engine.deterministicSeedBytes)
        .toList());

    // Create a large-keyspace high-entropy deterministic 16-byte salt from the low-entropy seed
    // We don't need to persist this salt as we can re-create it from the password
    final salt = _engine.generateDeterministicRandom(seed);

    return _engine.passwordHash(salt, password);
  }

  Uint8List _prependNonceToCipherText(List<int> nonce, List<int> cipherText) {
    return appendToList(nonce, cipherText);
  }

  Uint8List? _secretBoxEncrypt(Uint8List message, SecureKey key) {
    // 24 bytes
    final nonce = _engine.generateSecretBoxNonce();

    final cipherText = _engine.secretBoxEncrypt(message, nonce, key);

    if (cipherText == null) {
      return null;
    }

    return _prependNonceToCipherText(nonce, cipherText);
  }

  Uint8List? _secretBoxDecrypt(Uint8List message, SecureKey key) {
    // 24 bytes
    final nonce = message.sublist(0, _engine.secretBoxNonceBytes);

    final cipherText = message.sublist(_engine.secretBoxNonceBytes);

    return _engine.secretBoxDecrypt(cipherText, nonce, key);
  }

  Uint8List? _boxEncrypt(
      Uint8List message, Uint8List publicKey, SecureKey secretKey) {
    // 24 bytes
    final nonce = _engine.generateBoxNonce();

    final cipherText = _engine.boxEncrypt(message, nonce, publicKey, secretKey);

    if (cipherText == null) {
      return null;
    }

    return _prependNonceToCipherText(nonce, cipherText);
  }

  Uint8List? _boxDecrypt(
      Uint8List message, Uint8List publicKey, SecureKey secretKey) {
    // 24 bytes
    final nonce = message.sublist(0, _engine.boxNonceBytes);

    final cipherText = message.sublist(_engine.boxNonceBytes);

    return _engine.boxDecrypt(cipherText, nonce, publicKey, secretKey);
  }

  Future<String?> _encryptConfigSetting(Uint8List data) async {
    final cipherText = _secretBoxEncrypt(data, await _configKey);

    if (cipherText == null) {
      return null;
    }

    return uint8ListToBase64(cipherText);
  }

  Future<Uint8List?> _decryptConfigSetting(String data) async {
    final cipherText = base64ToUint8List(data);
    return _secretBoxDecrypt(cipherText, await _configKey)!;
  }

  Uint8List? _encryptForStickerDocsServer(Uint8List message) {
    // 48 bytes
    return _boxEncrypt(
        message, stickerDocsPublicKey, _ephemeralAccountKeyPair.secretKey);
  }

  Uint8List? _decryptFromStickerDocsServer(Uint8List message) {
    return _boxDecrypt(
        message, stickerDocsPublicKey, _ephemeralAccountKeyPair.secretKey);
  }

  Future<Uint8List?> encryptForMe(Uint8List message) async {
    final dataKeyPair = await _dataKeyPair;
    return _boxEncrypt(message, dataKeyPair.publicKey, dataKeyPair.secretKey);
  }

  Future<Uint8List?> decryptFromMe(Uint8List message) async {
    final dataKeyPair = await _dataKeyPair;
    return _boxDecrypt(message, dataKeyPair.publicKey, dataKeyPair.secretKey);
  }

  Future<Uint8List?> encryptForOtherUser(
      Uint8List message, Uint8List theirPublicKey) async {
    final dataKeyPair = await _dataKeyPair;

    return _boxEncrypt(message, theirPublicKey, dataKeyPair.secretKey);
  }

  Future<Uint8List?> decryptFromOtherUser(
      Uint8List message, Uint8List theirPublicKey) async {
    final dataKeyPair = await _dataKeyPair;

    return _boxDecrypt(message, theirPublicKey, dataKeyPair.secretKey);
  }

  Future<Uint8List?> encryptForReportingHarm(Uint8List message) async {
    final dataKeyPair = await _dataKeyPair;
    return _boxEncrypt(message, reportHarmPublicKey, dataKeyPair.secretKey);
  }

  // If we change our email we need to update the password too
  Uint8List? _generateEncryptedAuthKey(String email, String password) {
    // 32 bytes
    final authKey = _deriveDeterministicKey(email, password);

    // 72 bytes
    return _encryptForStickerDocsServer(authKey.extractBytes());
  }

  Future<RegisterRequest?> generateRegistrationData(
      String name, String email, String password, String? token) async {
    // 72 bytes
    final authKey = _generateEncryptedAuthKey(email, password);

    if (authKey == null) {
      logger.e('Could not generate an auth key');
      return null;
    }

    // 32 bytes for key and 16 bytes for salt
    final saltAndKey = _deriveKey(password);

    final dataKeyPair = await _dataKeyPair;
    final signingKeyPair = await _signingKeyPair;

    // 72 bytes
    final encryptedDataPrivateKey =
        _secretBoxEncrypt(dataKeyPair.secretKey.extractBytes(), saltAndKey.key);

    if (encryptedDataPrivateKey == null) {
      return null;
    }

    // 104 bytes
    final encryptedSigningPrivateKey = _secretBoxEncrypt(
        signingKeyPair.secretKey.extractBytes(), saltAndKey.key);

    if (encryptedSigningPrivateKey == null) {
      return null;
    }

    // We no longer need this key
    saltAndKey.key.dispose();

    return RegisterRequest(
        name: name,
        email: email,
        authPublicKey: _ephemeralAccountKeyPair.publicKey,
        authKey: authKey,
        dataPublicKey: dataKeyPair.publicKey,
        encryptedDataPrivateKey: encryptedDataPrivateKey,
        signingPublicKey: signingKeyPair.publicKey,
        encryptedSigningPrivateKey: encryptedSigningPrivateKey,
        keySalt: saltAndKey.salt,
        token: token);
  }

  Future<bool> decryptRegisterVerifyResponseAndPersist(
      Uint8List message) async {
    final plainText = _decryptFromStickerDocsServer(message);

    if (plainText == null) {
      return false;
    }

    final response =
        RegisterVerifyResponse.deserialize(uint8ListToString(plainText));

    logger.t(
        'Signing private key: ${base64Encode(response.requestSigningPrivateKey)}');

    await setApiRequestSigningPrivateKey(response.requestSigningPrivateKey);

    return true;
  }

  Future<bool> setApiRequestSigningPrivateKey(Uint8List privateKey) async {
    // Clear this cached key
    _apiRequestSigningPrivateKey = null;

    final encryptedRequestSigningKey = await _encryptConfigSetting(privateKey);

    if (encryptedRequestSigningKey == null) {
      return false;
    }

    await config.setRequestSigningPrivateKey(encryptedRequestSigningKey);
    return true;
  }

  LoginRequest? generateLoginData(String email, String password) {
    _ephemeralPassword = password;

    // 72 bytes
    final authKey = _generateEncryptedAuthKey(email, password);

    if (authKey == null) {
      logger.e('Could not generate an auth key');
      return null;
    }

    return LoginRequest(
        email: email,
        authPublicKey: _ephemeralAccountKeyPair.publicKey,
        authKey: authKey);
  }


  ChallengeRequest? generateChallengeRequestData(String email, String password) {
    _ephemeralPassword = password;

    // 72 bytes
    final authKey = _generateEncryptedAuthKey(email, password);

    if (authKey == null) {
      logger.e('Could not generate an auth key');
      return null;
    }

    return ChallengeRequest(
        authPublicKey: _ephemeralAccountKeyPair.publicKey,
        authKey: authKey);
  }

  ChangePasswordRequest? generateChangePasswordRequest(
      String email, String existingPassword) {
    // 72 bytes
    final authKey = _generateEncryptedAuthKey(email, existingPassword);

    if (authKey == null) {
      logger.e('Could not generate an auth key');
      return null;
    }


    return ChangePasswordRequest(
        authPublicKey: _ephemeralAccountKeyPair.publicKey,
        authKey: authKey);
  }

   ChangePasswordRequest? generateChangePasswordVerifyRequest(
      String email, String newPassword) {
     // 72 bytes
    final authKey = _generateEncryptedAuthKey(email, newPassword);

    if (authKey == null) {
      logger.e('Could not generate an auth key');
      return null;
    }

    return ChangePasswordRequest(
        authPublicKey: _ephemeralAccountKeyPair.publicKey,
        authKey: authKey);
  }

  Uint8List? generateAuthChallengeResponse(String challengeResponse) {
    // 46 bytes
    final encryptedChallengeResponse =
        _encryptForStickerDocsServer(stringToUint8List(challengeResponse));

    if (encryptedChallengeResponse == null) {
      logger.e('Could not generate an auth challenge response');
    }

    return encryptedChallengeResponse;
  }

  Future<bool> decryptLoginVerifyResponseAndPersist(Uint8List message) async {
    final plainText = _decryptFromStickerDocsServer(message);

    if (plainText == null) {
      return false;
    }

    final response =
        LoginVerifyResponse.deserialize(uint8ListToString(plainText));

    final key = _engine.passwordHash(response.keySalt, _ephemeralPassword!);
    _ephemeralPassword = null;

    await _setDataKeyPair(_decryptKeyPair(
        key, response.encryptedDataPrivateKey, response.dataPublicKey));

    await _setSigningKeyPair(_decryptKeyPair(
        key, response.encryptedSigningPrivateKey, response.signingPublicKey));

    // We no longer need this key
    key.dispose();

    await config.setUserId(response.userId);

    logger.t(
        'Signing private key: ${base64Encode(response.requestSigningPrivateKey)}');

    await setApiRequestSigningPrivateKey(response.requestSigningPrivateKey);

    return true;
  }

  KeyPair _decryptKeyPair(
      SecureKey secretKey, Uint8List encryptedPublicKey, Uint8List publicKey) {
    final privateKey = _secretBoxDecrypt(encryptedPublicKey, secretKey)!;
    final decryptedSecretKey = _engine.loadSecureKey(privateKey);
    return KeyPair(secretKey: decryptedSecretKey, publicKey: publicKey);
  }

  Uint8List? encryptFile(File file, Uint8List data) {
    // If there is already an encryption key for the file use that
    if (file.encryptionKey != null) {
      return _secretBoxEncrypt(
          data, _engine.loadSecureKey(file.encryptionKey!));
    }

    // Otherwise create a new one

    // 32 bytes
    final key = _engine.generateSecretBoxSecureKey();

    file.encryptionKey = key.extractBytes();

    return _secretBoxEncrypt(data, key);
  }

  Future<Uint8List> decryptFile(Uint8List encryptionKey, Uint8List data) async {
    return _secretBoxDecrypt(data, _engine.loadSecureKey(encryptionKey))!;
  }

  Future<String> signData(Uint8List message) async {
    final signingKeyPair = await _signingKeyPair;
    final signature = _engine.sign(message, signingKeyPair.secretKey);
    return uint8ListToBase64(signature);
  }

  Future<bool> verifySignedData(Uint8List message, Uint8List signature) async {
    final signingKeyPair = await _signingKeyPair;

    return _engine.verifySignature(
        message, signature, signingKeyPair.publicKey);
  }

  Future<Invitation> createInvitation(String invitationId) async {
    final userId = (await config.userId)!;
    final dataKeyPair = await _dataKeyPair;

    // public = 32 bytes, private = 64 bytes
    final signingKeyPair = _engine.generateSigningKeyPair();

    return Invitation(
      userId,
      invitationId,
      dataKeyPair.publicKey,
      signingKeyPair.publicKey,
      signingKeyPair.secretKey.extractBytes(),
    );
  }

  InvitationRequest? createInvitationRequest(
      Invitation invitation,
      Sticker sticker,
      Uint8List stickerImage,
      String recipientName,
      String recipientEmail,
      String passphrase) {
    // 32 bytes for key and 16 bytes for salt
    final saltAndKey = _deriveKey(passphrase);

    // 351 bytes
    final invitationBytes = stringToUint8List(invitation.serialize());

    // 391 bytes
    final encryptedInvitation =
        _secretBoxEncrypt(invitationBytes, saltAndKey.key);

    if (encryptedInvitation == null) {
      return null;
    }

    return InvitationRequest(
      invitationId: invitation.invitationId,
      recipientName: recipientName,
      recipientEmail: recipientEmail,
      sticker: sticker,
      stickerImage: stickerImage,
      signingPublicKey: invitation.signingPublicKey,
      challengeSalt: saltAndKey.salt,
      challenge: encryptedInvitation,
    );
  }

  Future<Invitation?> decryptInvitation(
      EncryptedInvitation encryptedInvitation, String passphrase) async {
    // 32 bytes
    final key =
        _engine.passwordHash(encryptedInvitation.challengeSalt, passphrase);

    // 391 bytes
    final invitationBytes =
        _secretBoxDecrypt(encryptedInvitation.challenge, key);

    if (invitationBytes == null) {
      return null;
    }

    return Invitation.deserialize(uint8ListToString(invitationBytes));
  }

  Future<Uint8List> createInvitationSignature(Invitation invitation) async {
    final dataKeyPair = await _dataKeyPair;
    final userId = (await config.userId)!;

    final signingKeyPair = KeyPair(
        secretKey: _engine.loadSecureKey(invitation.signingPrivateKey),
        publicKey: invitation.signingPublicKey);

    final messageToSign = BytesBuilder();
    messageToSign.add(stringToUint8List(userId));
    messageToSign.add(stringToUint8List(invitation.invitationId));
    messageToSign.add(dataKeyPair.publicKey);

    // 64 bytes
    final signature =
        _engine.sign(messageToSign.toBytes(), signingKeyPair.secretKey);

    return signature;
  }

  bool verifyTrustChallengeResult(
      InvitedUser invitation, InvitationResponse challenge) {
    final signedMessage = BytesBuilder();
    signedMessage.add(stringToUint8List(challenge.userId));
    signedMessage.add(stringToUint8List(invitation.id));
    signedMessage.add(challenge.publicKey);

    return _engine.verifySignature(signedMessage.toBytes(), challenge.signature,
        invitation.signingPublicKey!);
  }

  Future<String?> signApiRequest(
      String url, String headers, String? body) async {
    if (_apiRequestSigningPrivateKey == null) {
      final encryptedSigningPrivateKey = await config.requestSigningPrivateKey;

      if (encryptedSigningPrivateKey == null) {
        return null;
      }

      final signingPrivateKey =
          await _decryptConfigSetting(encryptedSigningPrivateKey);

      if (signingPrivateKey == null) {
        return null;
      }

      _apiRequestSigningPrivateKey = _engine.loadSecureKey(signingPrivateKey);
    }

    final messageToSign = BytesBuilder();

    // e.g. GET/account
    messageToSign.add(stringToUint8List(url));

    // e.g. {'Client-Id':'8a530d02-babf-47c4-8b20-93fc993ac6c6','User-Agent':'SD-App macOS/1','User-Id':'783f9540-f8bf-4669-9819-53f3982a01f0'}
    messageToSign.add(stringToUint8List(headers));

    // Also sign the body if there is one
    if (body != null) {
      messageToSign.add(stringToUint8List(body));
    }

    // logger.i('Signed data: ${base64Encode(messageToSign.toBytes())}');

    // 64 bytes
    final signature =
        _engine.sign(messageToSign.toBytes(), _apiRequestSigningPrivateKey!);

    return uint8ListToBase64(signature);
  }
}
