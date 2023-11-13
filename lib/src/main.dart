import 'dart:typed_data';

import 'package:get_it/get_it.dart';

import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/clock.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/services/crypto_engine.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/sync_shared.dart';
import 'package:stickerdocs_core/src/services/sync.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/app_state.dart';
import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/utils.dart';

// Expose global services
ConfigService get config => GetIt.I.get<ConfigService>();
CryptoService get crypto => GetIt.I.get<CryptoService>();
APIService get api => GetIt.I.get<APIService>();
AppLogic get logic => GetIt.I.get<AppLogic>();

class CoreConfig {
  final String apiBaseUrl;
  final String appName;
  final String appVersion;
  final AppState appState;
  final Uint8List stickerDocsPublicKey;
  final Uint8List reportHarmPublicKey;

  CoreConfig({
    required this.apiBaseUrl,
    required this.appName,
    required this.appVersion,
    required this.appState,
    required this.stickerDocsPublicKey,
    required this.reportHarmPublicKey,
  });
}

Future<void> initCore(CoreConfig config) async {
  await populateBaseDataPath();

  // We probably want to make use of the config during the lifetime of the app
  await initConfig();

  // Set up logging
  attachLogger();

  // It is most likely we will use crypto for something during the lifetime of the app
  await initCryptoEngine();

  registerSingletons(config);
}

void registerSingletons(CoreConfig config) {
  GetIt.I.registerLazySingleton(() => ClockService());
  GetIt.I.registerLazySingleton(() => DBService());
  GetIt.I.registerLazySingleton(() => ConfigService());
  GetIt.I.registerLazySingleton(() => CryptoEngine());
  GetIt.I.registerLazySingleton(() =>
      CryptoService(config.stickerDocsPublicKey, config.reportHarmPublicKey));
  GetIt.I.registerLazySingleton(() => APIService(
        config.apiBaseUrl,
        config.appName,
        config.appVersion,
      ));
  GetIt.I.registerLazySingleton(() => FileService());
  GetIt.I.registerLazySingleton(() => SyncService());
  GetIt.I.registerLazySingleton(() => SyncSharedService());
  GetIt.I.registerLazySingleton(() => AppLogic(config.appState));
}
