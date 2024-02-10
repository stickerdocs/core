import 'dart:async';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';

import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/utils.dart';

late String _baseDataPath;
late String _profileName;
late String _dataPath;

Future<void> loadProfile(String baseDataPath) async {
  _baseDataPath = baseDataPath;

  var profileFile = File(join(_baseDataPath, 'profile'));

  if (await profileFile.exists()) {
    _profileName = await profileFile.readAsString();
  } else {
    _profileName = 'new';
    await profileFile.writeAsString(_profileName);
  }

  // Create the directory if required
  await Directory(join(_baseDataPath, _profileName, 'data'))
      .create(recursive: true);

  _dataPath = join(_baseDataPath, _profileName);

  configureLogging(_dataPath);
  logger.i('Data path: $_dataPath');
}

Future<void> setProfile(ConfigService config, DBService db, String? email,
    bool isRegistration) async {
  final lastProfileName = await config.lastProfile;
  final newProfileName = email == null
      ? 'new'
      : CryptoService.sha256(stringToUint8List(email.toLowerCase()));

  // Were we previously logged in with this email?
  if (newProfileName == lastProfileName) {
    // Nothing to do
    return;
  }

  _profileName = newProfileName;

  final profileFile = File(join(_baseDataPath, 'profile'));
  await profileFile.writeAsString(_profileName);

  await db.close();

  // Were we not previously logged in and we just registered (i.e. this is a new profile)?
  if (lastProfileName == null && isRegistration) {
    // Rename the profile path to this profile name
    await Directory(join(_baseDataPath, 'new'))
        .rename(join(_baseDataPath, _profileName));
  }

  await loadProfile(_baseDataPath);
  config.reRoot();

  await config.setLastProfile(email == null ? null : newProfileName);
}

enum ConfigKey {
  firstRun,
  dataPublicKey,
  dataPrivateKey,
  signingPublicKey,
  signingPrivateKey,
  clientId,
  userId,
  userEmail,
  requestSigningPrivateKey,
  subscriptionActive,
  lastProfile,
  loggingLevel,
}

extension ConfigKeyExtensions on ConfigKey {
  String format() {
    return toString().split('.')[1];
  }
}

class ConfigService {
  final DBService _db = GetIt.I.get<DBService>();

  String dbPath = join(_dataPath, 'db');
  String dataPath = join(_dataPath, 'data');
  String dataOutboxPath = join(_dataPath, 'outbox');
  String dataInboxPath = join(_dataPath, 'inbox');
  String tempPath = join(_dataPath, 'temp');

  String? _dataPublicKey;
  String? _dataPrivateKey;
  String? _signingPublicKey;
  String? _signingPrivateKey;
  String? _userId;
  String? _userEmail;
  String? _clientId;
  String? _requestSigningPrivateKey;
  String? _lastProfile;
  Level? _loggingLevel;

  Future<bool> get isFirstRun async {
    return await _db.getConfig(ConfigKey.firstRun) != null;
  }

  Future<void> setDataPublicKey(String? value) async {
    await _db.setConfig(ConfigKey.dataPublicKey, value);
    _dataPublicKey = value;
  }

  Future<String?> get dataPublicKey async {
    _dataPublicKey ??= await _db.getConfig(ConfigKey.dataPublicKey);
    return _dataPublicKey;
  }

  Future<void> setDataPrivateKey(String? value) async {
    await _db.setConfig(ConfigKey.dataPrivateKey, value);
    _dataPrivateKey = value;
  }

  Future<String?> get dataPrivateKey async {
    _dataPrivateKey ??= await _db.getConfig(ConfigKey.dataPrivateKey);
    return _dataPrivateKey;
  }

  Future<void> setSigningPublicKey(String? value) async {
    await _db.setConfig(ConfigKey.signingPublicKey, value);
    _signingPublicKey = value;
  }

  Future<String?> get signingPublicKey async {
    _signingPublicKey ??= await _db.getConfig(ConfigKey.signingPublicKey);
    return _signingPublicKey;
  }

  Future<void> setSigningPrivateKey(String? value) async {
    await _db.setConfig(ConfigKey.signingPrivateKey, value);
    _signingPrivateKey = value;
  }

  Future<String?> get signingPrivateKey async {
    if (_signingPrivateKey != null) {
      return _signingPrivateKey;
    }

    _signingPrivateKey = await _db.getConfig(ConfigKey.signingPrivateKey);
    return _signingPrivateKey;
  }

  Future<String> get clientId async {
    // Retrieve from DB
    _clientId ??= await _db.getConfig(ConfigKey.clientId);

    // Or generate and store a new one
    if (_clientId == null) {
      _clientId = newUuid();
      await _db.setConfig(ConfigKey.clientId, _clientId!);
    }

    return _clientId!;
  }

  Future<void> persistClientId() async {
    if (await _db.getConfig(ConfigKey.clientId) != null) {
      return;
    }

    await _db.setConfig(ConfigKey.clientId, _clientId);
  }

  Future<void> setUserId(String? value) async {
    await _db.setConfig(ConfigKey.userId, value);
    _userId = value;
  }

  Future<String?> get userId async {
    _userId ??= await _db.getConfig(ConfigKey.userId);
    return _userId;
  }

  Future<void> setUserEmail(String? value) async {
    await _db.setConfig(ConfigKey.userEmail, value);
    _userEmail = value;
  }

  Future<String?> get userEmail async {
    _userEmail ??= await _db.getConfig(ConfigKey.userEmail);
    return _userEmail;
  }

  Future<void> setRequestSigningPrivateKey(String? value) async {
    await _db.setConfig(ConfigKey.requestSigningPrivateKey, value);
    _requestSigningPrivateKey = value;
  }

  Future<String?> get requestSigningPrivateKey async {
    _requestSigningPrivateKey ??=
        await _db.getConfig(ConfigKey.requestSigningPrivateKey);
    return _requestSigningPrivateKey;
  }

  Future<void> setFirstRunCompleted() async {
    await _db.setConfig(ConfigKey.firstRun, null);
  }

  Future<void> setLastProfile(String? value) async {
    await _db.setConfig(ConfigKey.lastProfile, value);
    _lastProfile = value;
  }

  Future<String?> get lastProfile async {
    _lastProfile ??= await _db.getConfig(ConfigKey.lastProfile);
    return _lastProfile;
  }

  Future<void> logout() async {
    await setRequestSigningPrivateKey(null);
    await setDataPrivateKey(null);
    await setSigningPrivateKey(null);
    await setDataPublicKey(null);
    await setSigningPublicKey(null);
    await setUserId(null);
    await setUserEmail(null);
  }

  Future<void> setLoggingLevel(Level value) async {
    await _db.setConfig(ConfigKey.loggingLevel, value.toString());
    _loggingLevel = value;
    configureLogging(_dataPath);
  }

  Future<Level> get loggingLevel async {
    final stringValue = await _db.getConfig(ConfigKey.loggingLevel);

    if (stringValue == null) {
      _loggingLevel = Level.debug;
    } else {
      _loggingLevel =
          Level.values.firstWhere((value) => value.toString() == stringValue);
    }

    return _loggingLevel!;
  }

  void reRoot() {
    dbPath = join(_dataPath, 'db');
    dataPath = join(_dataPath, 'data');
    dataOutboxPath = join(_dataPath, 'outbox');
    dataInboxPath = join(_dataPath, 'inbox');
    tempPath = join(_dataPath, 'temp');
  }
}
