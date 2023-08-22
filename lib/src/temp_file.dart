import 'dart:io' as io;
import 'dart:typed_data';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart';

import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/utils.dart';

ConfigService get _config {
  return GetIt.I<ConfigService>();
}

Future<void> _createDirectory(String path) async {
  final directory = io.Directory(path);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
}

String getTemporaryDirectory() {
  return io.Directory(_config.tempPath).path;
}

Future<void> clearTemporaryFiles() async {
  final directory = io.Directory(_config.tempPath);

  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }

  await directory.create(recursive: true);
}

Future<io.File> writeTemporaryFile(Uint8List data) async {
  await _createDirectory(_config.tempPath);

  final file = io.File(join(_config.tempPath, newUuid()));
  await file.writeAsBytes(data, flush: true);
  return file;
}

String _getFileTemporaryPath(File file) {
  if (file.name != null) {
    return join(getTemporaryDirectory(), file.id, file.name);
  }

  return join(getTemporaryDirectory(), file.id);
}

Future<String> writeFileToTemp(File file) async {
  final filePath = _getFileTemporaryPath(file);

  await _createDirectory(dirname(filePath));
  await file.getFile().copy(filePath);

  return filePath;
}
