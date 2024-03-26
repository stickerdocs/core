// ignore_for_file: unnecessary_type_check

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stickerdocs_core/src/models/api/file_get_response.dart';

void main() {
  test(
      'FileGetResponse instance should not be of type FileNotFoundFileGetResponse',
      () async {
    final notFound = FileNotFoundFileGetResponse.create();
    final fileResponse = FileGetResponse(
      created: DateTime.now(),
      size: 0,
      fileChunks: [],
      signature: Uint8List.fromList([0x00]),
    );

    // This is a sanity check

    expect(notFound is FileNotFoundFileGetResponse, isTrue);
    expect(notFound is FileGetResponse, isTrue);

    expect(fileResponse is FileNotFoundFileGetResponse, isFalse);
    expect(fileResponse is FileGetResponse, isTrue);
  });
}
