import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:nanoid/nanoid.dart';

final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
final isMobile = !isDesktop;

String? _platformName;

String get platformName {
  if (_platformName != null) {
    return _platformName!;
  }

  if (Platform.isWindows) {
    _platformName = 'Windows';
  } else if (Platform.isIOS) {
    _platformName = 'iOS';
  } else if (Platform.isMacOS) {
    _platformName = 'macOS';
  } else if (Platform.isAndroid) {
    _platformName = 'Android';
  } else if (Platform.isLinux) {
    _platformName = 'Linux';
  } else {
    _platformName = 'Unknown';
  }

  return _platformName!;
}

const _base64Codec = Base64Codec.urlSafe();
const String defaultFilename = 'Untitled';

late Logger logger;
bool _loggerInitialised = false;

void configureLogging(String dataPath) {
  if (_loggerInitialised) {
    logger.close();
  }

  List<LogOutput> logOutputs = [ConsoleOutput()];

  // There is an issue with logging to file in Windows
  // Changing profiles causes the logger to not be disposed of properly
  // Could just log a level down perhaps?
  if (!Platform.isWindows) {
    logOutputs.add(FileOutput(file: File(join(dataPath, 'log.txt'))));
  }

  logger = Logger(
      printer: SimplePrinter(),
      output: MultiOutput(logOutputs),
      level: kDebugMode ? Level.trace : Level.info);

  _loggerInitialised = true;
}

Uint8List appendToList(List<int> list1, List<int> list2) {
  var result = BytesBuilder();
  result.add(list1);
  result.add(list2);
  return result.toBytes();
}

// UTF-16
Int8List stringToInt8List(String input) {
  return Int8List.fromList(input.codeUnits);
}

Uint8List stringToUint8List(String input) {
  return Uint8List.fromList(input.codeUnits);
}

String uint8ListToString(Uint8List input) {
  return String.fromCharCodes(input);
}

String uint8ListToBase64(Uint8List input) {
  return _base64Codec.encode(input);
}

Uint8List base64ToUint8List(String input) {
  return _base64Codec.decode(input);
}

String newUuid() {
  return customAlphabet(
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz', 22);
}

DateTime isoDateNow() {
  return DateTime.now().toUtc();
}

String isoDateToString(DateTime date) {
  return date.toIso8601String().replaceAll('Z', '');
}

String isoDateToStringNow() {
  return isoDateNow().toIso8601String().replaceAll('Z', '');
}

DateTime? fromIsoDateString(String? date) {
  if (date == null) {
    return null;
  }

  return DateTime.parse(date);
}

enum CustomContentType {
  eventData,
}

extension CustomContentTypeExtensions on CustomContentType {
  String format() {
    return 'stickerdocs/${toString().split('.')[1].toLowerCase()}';
  }
}

String formatInvitationToken(String token) {
  return token.replaceAll('-', '').replaceAll('.', '').trim();
}
