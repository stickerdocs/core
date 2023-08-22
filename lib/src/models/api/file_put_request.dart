import 'package:stickerdocs_core/src/models/file_chunk.dart';
import 'package:stickerdocs_core/src/utils.dart';

class FilePutRequest {
  final String fileId;
  final DateTime created;
  final int size;
  final List<FileChunk> fileChunks;
  String? signature;

  FilePutRequest({
    required this.fileId,
    required this.created,
    required this.size,
    required this.fileChunks,
  });

  Map<String, dynamic> toJson() {
    var map = {
      'file_id': fileId,
      'created': isoDateToString(created),
      'size': size,
      'chunks': fileChunks.map((fileChunk) => fileChunk.md5).toList()
    };

    if (signature != null) {
      map['signature'] = signature!;
    }

    return map;
  }
}
