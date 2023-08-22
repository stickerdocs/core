import 'package:mockito/annotations.dart';
import 'package:sodium/sodium.dart';

import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/crypto_engine.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/services/sync.dart';

@GenerateMocks([
  CryptoEngine,
  DBService,
  APIService,
  FileService,
  AppLogic,
  SyncService,
  ConfigService,
  SecureKey,
])
void main() {}
