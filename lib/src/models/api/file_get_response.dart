import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:stickerdocs_core/src/models/file_chunk.dart';
import 'package:stickerdocs_core/src/utils.dart';

class FileGetResponse {
  final DateTime created;
  final int size;
  final List<FileChunk> fileChunks;
  final Uint8List signature;

  const FileGetResponse(
      {required this.created,
      required this.size,
      required this.fileChunks,
      required this.signature});

  // TODO: https://stackoverflow.com/questions/60860270/how-to-get-json-array-in-flutter-dart
  FileGetResponse.fromJson(
      Map<String, dynamic> map, String fileId, String? sourceUserId)
      : created = fromIsoDateString(map['created'])!,
        size = map['size'],
        fileChunks = List.castFrom(map['chunks'])
            .mapIndexed((index, fileChunk) => FileChunk(
                fileId: fileId,
                index: index,
                sourceUserId: sourceUserId,
                md5: fileChunk['md5'],
                url: fileChunk['url'],
                urlCreated: isoDateNow()))
            .toList(),
        signature = base64ToUint8List(map['signature']);

  static FileGetResponse deserialize(
      String data, String fileId, String? sourceUserId) {
    Map<String, dynamic> decoded = jsonDecode(data);
    return FileGetResponse.fromJson(decoded, fileId, sourceUserId);
  }
}
