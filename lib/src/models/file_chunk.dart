import 'package:stickerdocs_core/src/utils.dart';

class FileChunk {
  String fileId;
  int index;
  String? sourceUserId;
  String md5;
  String? url;
  DateTime? urlCreated;
  int? size;
  bool uploaded = false;
  bool downloaded = false;
  int attempt = 0;

  FileChunk({
    required this.fileId,
    required this.index,
    required this.sourceUserId,
    required this.md5,
    this.url,
    this.urlCreated,
    this.size,
  });

  static FileChunk fromMap(Map<String, dynamic> map) {
    final fileChunk = FileChunk(
      fileId: map['file_id'],
      index: map['chunk_index'],
      sourceUserId: map['source_user_id'],
      md5: map['md5'],
      url: map['url'],
      urlCreated: fromIsoDateString(map['url_created']),
      size: map['size'],
    );

    fileChunk.uploaded = (map['uploaded'] ?? 0) == 1;
    fileChunk.downloaded = (map['downloaded'] ?? 0) == 1;
    fileChunk.attempt = map['attempt'] ?? 0;

    return fileChunk;
  }

  static List<FileChunk> fromMaps(List<Map<String, dynamic>> maps) {
    return List.generate(maps.length, (i) {
      return FileChunk.fromMap(maps[i]);
    });
  }
}
