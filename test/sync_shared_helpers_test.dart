import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/services/sync_shared.dart';

import 'mock.mocks.dart';
import 'test_data.dart' as data;

void main() {
  late SyncSharedService service;

  setUp(() {
    GetIt.I.registerSingleton<DBService>(MockDBService());
    GetIt.I.registerSingleton<APIService>(MockAPIService());
    GetIt.I.registerSingleton<FileService>(MockFileService());
    GetIt.I.registerSingleton<SyncSharedService>(SyncSharedService());

    service = GetIt.I.get<SyncSharedService>();
  });

  tearDown(() {
    GetIt.I.reset();
  });

  test('groupEvents should group as expected and perform security filtering', () {
    final result = service.groupEvents(data.groupTestFilterEvents).toList();

    expect(result.length, equals(6));
    expect(result[0].length, equals(1));
    expect(result[1].length, equals(1));
    expect(result[2].length, equals(4));
    expect(result[3].length, equals(2));
    expect(result[4].length, equals(1));
    expect(result[5].length, equals(1));
  });
}
