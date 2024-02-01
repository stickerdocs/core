// TODO: what about the retries, are we going to do something about the counts going up?
// 2x background upload workers?
// 2x background download workers?
// Should we be using for { await } or that waitforall thing. Does this do an await and then another?, slower

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;

import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/main.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/file_chunk.dart';
import 'package:stickerdocs_core/src/models/api/file_put_request.dart';
import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/utils.dart';

// Each chunk is 4MB, which is 4 * 1024^2 bytes, which is 4,194,304 bytes
// Max file size is 10GB, which is 10 * 1024^3 bytes, which is 10,737,418,240 bytes
// Therefore the maximum number of chunks permitted is 2,560 (10 * 1024^3 / 4 * 1024^2)
// This fits into the permitted storage for DynamoDB items
const chunkSize = 4194304;

const urlExpirationDuration = Duration(hours: 1);

class FileService {
  final DBService _db = GetIt.I.get<DBService>();
  final APIService _api = GetIt.I.get<APIService>();

  AppLogic? _logicInstance;

  AppLogic get _logic {
    _logicInstance ??= GetIt.I.get<AppLogic>();
    return _logicInstance!;
  }

  Future<void> uploadFiles() async {
    final filesToUpload = await _db.getFilesToUpload();

    for (final file in filesToUpload) {
      await uploadFile(file);
    }
  }

  Future<void> downloadFiles() async {
    // On desktop download all the files.
    // On mobile only download when files are requested.
    if (isDesktop) {
      final filesToDownload = await _db.getFilesToDownload();

      for (final file in filesToDownload) {
        await downloadFile(file);
      }
    }
  }

  Future<bool> uploadFile(File file) async {
    if (file.uploaded == true) {
      // Nothing to do
      return true;
    }

    // We expect these conditions to be met prior to uploading the file
    if (file.sha256 == null) {
      return false;
    }

    // We can only upload the file if it exists on disk
    if (!await file.getFile().exists()) {
      return false;
    }

    var fileChunksToUpload = await _getFileChunksToUpload(file);

    if (fileChunksToUpload == null) {
      // Could not get or create file chunks
      return false;
    }

    for (final fileChunk in fileChunksToUpload) {
      // Was there a problem uploading the chunk?
      if (!await _uploadFileChunk(fileChunk)) {
        return false;
      }
    }

    // Check to make sure the file has been fully uploaded
    fileChunksToUpload = await _getFileChunksToUpload(file);

    if (fileChunksToUpload == null) {
      // Could not get or create file chunks
      return false;
    }

    if (_haveAllFileChunksBeenUploaded(fileChunksToUpload)) {
      await _fileUploadedSuccess(file);
      return true;
    }

    return true;
  }

  Future<List<FileChunk>?> _getFileChunksToUpload(File file) async {
    var fileChunks = await _db.getFileChunksForUpload(file.id);

    // Regardless of what chunks have been uploaded, if we have chunked the file
    // then we do not want to encrypt and chunk it again
    if (fileChunks.isNotEmpty) {
      return fileChunks.where(_isFileChunkNotUploaded).toList();
    }

    final encryptedFileData = await _encryptFileForUpload(file);

    if (encryptedFileData == null) {
      return null;
    }

    // Save the encryption key
    await _db.save(file);

    fileChunks = await _createFileUploadChunks(encryptedFileData, file.id);

    // Store chunk hashes in DB
    await _db.addFileChunkUploadEntries(fileChunks);

    // Create the file upload request
    final request = FilePutRequest(
        fileId: file.id,
        created: file.created,
        size: encryptedFileData.length,
        fileChunks: fileChunks);

    // Sign the request
    request.signature =
        await crypto.signData(stringToUint8List(json.encode(request)));

    final chunkUrls = await _api.putFile(request);

    if (chunkUrls.isEmpty) {
      return null;
    }

    fileChunks.forEachIndexed((index, fileChunk) {
      fileChunk.url = chunkUrls[index];
    });

    await _db.updateFileChunkUploadUrls(fileChunks);

    return fileChunks;
  }

  bool _isFileChunkNotUploaded(FileChunk fileChunk) {
    return !fileChunk.uploaded;
  }

  Future<void> _refreshExpiredUploadUrl(FileChunk fileChunk) async {
    if (!_hasFileChunkUrlExpired(fileChunk)) {
      return;
    }

    await _refreshFileChunkUploadUrl(fileChunk);
    await _db.updateFileChunkUploadUrls([fileChunk]);
  }

  bool _hasFileChunkUrlExpired(FileChunk fileChunk) {
    if (fileChunk.urlCreated == null) {
      return true;
    }

    return fileChunk.urlCreated!
        .add(urlExpirationDuration)
        .isBefore(isoDateNow());
  }

  Future<void> _refreshFileChunkUploadUrl(FileChunk fileChunk) async {
    final url = await _api.putFileChunk(fileChunk);

    if (url != null) {
      fileChunk.url = url;
    }
  }

  Future<Uint8List?> _encryptFileForUpload(File file) async {
    final data = await file.getFile().readAsBytes();
    final compressedData = io.GZipCodec().encode(data);
    final usingCompression = compressedData.length < data.length;
    final formattedData = BytesBuilder();

    if (usingCompression) {
      formattedData.add([0x01]);
      formattedData.add(Uint8List.fromList(compressedData));
    } else {
      formattedData.add([0x00]);
      formattedData.add(Uint8List.fromList(data));
    }

    return crypto.encryptFile(file, formattedData.toBytes());
  }

  Future<List<FileChunk>> _createFileUploadChunks(
      Uint8List encryptedFileData, String fileId) async {
    List<FileChunk> fileChunks = [];
    var chunkIndex = 0;

    final documentDataPath = join(config.dataOutboxPath, fileId);
    await io.Directory(documentDataPath).create(recursive: true);

    // Chunk the file
    for (var chunkOffset = 0;
        chunkOffset < encryptedFileData.length;
        chunkOffset += chunkSize) {
      final outputFile = io.File(join(documentDataPath, chunkIndex.toString()));
      final data = _getChunkData(chunkOffset, chunkSize, encryptedFileData);

      await outputFile.writeAsBytes(data);

      // Hash the encrypted data for download integrity checks and for non-repudiation with the signature
      final hash = CryptoService.md5(data);

      fileChunks.add(FileChunk(
          fileId: fileId,
          index: chunkIndex,

          // The the logged-in user is always the source of uploaded chunks
          sourceUserId: null,
          md5: hash,
          size: data.length));

      chunkIndex++;
    }

    return fileChunks;
  }

  Uint8List _getChunkData(
      int chunkIndex, int chunkSize, Uint8List encryptedFile) {
    if (chunkIndex + chunkSize < encryptedFile.length) {
      return encryptedFile.sublist(chunkIndex, chunkIndex + chunkSize);
    }

    return encryptedFile.sublist(chunkIndex);
  }

  bool _haveAllFileChunksBeenUploaded(List<FileChunk> fileChunks) {
    return !fileChunks.any((fileChunk) => !fileChunk.uploaded);
  }

  Future<bool> _uploadFileChunk(FileChunk fileChunk) async {
    await _refreshExpiredUploadUrl(fileChunk);
    await _db.incrementFileChunkUploadCounter(fileChunk);

    final file = io.File(join(
        config.dataOutboxPath, fileChunk.fileId, fileChunk.index.toString()));
    final data = await file.readAsBytes();

    Map<String, String> headers = {
      'x-amz-storage-class': 'INTELLIGENT_TIERING',
      'Content-MD5': _formatAwsContentMd5(fileChunk.md5),
      'Content-Length': fileChunk.size.toString()
    };

    final client = http.Client();
    final uploadResponse = await client.put(Uri.parse(fileChunk.url!),
        headers: headers, body: data);
    final response =
        await processResponse('PUT', fileChunk.url!, headers, uploadResponse);

    if (response.statusCode != 200) {
      return false;
    }

    await _db.markFileChunkUploaded(fileChunk);

    await file.delete();

    return true;
  }

  String _formatAwsContentMd5(String md5) {
    return base64.encode(hex.decode(md5));
  }

  Future<void> _fileUploadedSuccess(File file) async {
    // Notify server so the file can be marked as read-only
    final result = await _api.fileUploadSuccessful(file.id);

    if (result != null) {
      await _logic.updateAccountDetails(result);
    }

    // Remove the outbox data
    await io.Directory(join(config.dataOutboxPath, file.id))
        .delete(recursive: true);

    await _db.markFileUploaded(file.id);
  }

  Future<bool> downloadFile(File file) async {
    if (file.downloaded == true) {
      // Nothing to do
      return true;
    }

    // We expect these conditions to be met prior to downloading the file
    if (file.encryptionKey == null) {
      return false;
    }

    return await downloadFileById(
        file.id, file.encryptionKey!, file.sourceUserId);
  }

  Future<bool> downloadFileById(String fileId, Uint8List encryptionKey,
      [String? sourceUserId]) async {
    var fileChunksToDownload =
        await _getFileChunksToDownload(fileId, sourceUserId);

    if (fileChunksToDownload == null) {
      // Could not get or create file chunks
      return false;
    }

    for (final fileChunk in fileChunksToDownload) {
      // Was there a problem downloading the chunk?
      if (!await _downloadFileChunk(fileChunk)) {
        return false;
      }
    }

    // Check to make sure the file has been fully downloaded
    fileChunksToDownload = await _getFileChunksToDownload(fileId, sourceUserId);

    if (fileChunksToDownload == null) {
      // Could not get or create file chunks
      return false;
    }

    if (_haveAllFileChunksBeenDownloaded(fileChunksToDownload)) {
      await _fileDownloadedSuccess(
          fileId, fileChunksToDownload.length, encryptionKey);
      return true;
    }

    return true;
  }

  Future<List<FileChunk>?> _getFileChunksToDownload(
      String fileId, String? sourceUserId) async {
    final fileChunks = await _db.getFileChunksForDownload(fileId);

    if (fileChunks.isNotEmpty) {
      return fileChunks.where(_isFileChunkNotDownloaded).toList();
    }

    final fileResponse = await _api.getFile(fileId, sourceUserId);

    if (fileResponse == null) {
      return null;
    }

    // TODO: Verify the signature prior to continuing

    await _db.addFileChunkDownloadEntries(
        fileResponse.fileChunks, sourceUserId);

    return fileResponse.fileChunks;
  }

  bool _isFileChunkNotDownloaded(FileChunk fileChunk) {
    return !fileChunk.downloaded;
  }

  Future<void> _refreshExpiredDownloadUrl(FileChunk fileChunk) async {
    if (!_hasFileChunkUrlExpired(fileChunk)) {
      return;
    }

    await _refreshFileChunkDownloadUrl(fileChunk);
    await _db.updateFileChunkUploadUrls([fileChunk]);
  }

  Future<void> _refreshFileChunkDownloadUrl(FileChunk fileChunk) async {
    final url = await _api.getFileChunk(fileChunk);

    if (url != null) {
      fileChunk.url = url;
    }
  }

  Future<bool> _downloadFileChunk(FileChunk fileChunk) async {
    await _refreshExpiredDownloadUrl(fileChunk);
    await _db.incrementFileChunkDownloadCounter(fileChunk);

    final client = http.Client();
    final downloadResponse = await client.get(Uri.parse(fileChunk.url!));
    final response =
        await processResponse('GET', fileChunk.url!, null, downloadResponse);

    if (response.statusCode != 200) {
      return false;
    }

    final hash = CryptoService.md5(response.bodyBytes);
    if (hash != fileChunk.md5) {
      // TODO: throw some exception, raise a notification
      return false;
    }

    final fileDataPath = join(config.dataInboxPath, fileChunk.fileId);
    await io.Directory(fileDataPath).create(recursive: true);

    final file = io.File(join(fileDataPath, fileChunk.index.toString()));
    await file.writeAsBytes(response.bodyBytes);

    await _db.markFileChunkDownloaded(fileChunk);

    return true;
  }

  bool _haveAllFileChunksBeenDownloaded(List<FileChunk> fileChunks) {
    return !fileChunks.any((fileChunk) => !fileChunk.downloaded);
  }

  Future<void> _fileDownloadedSuccess(
      String fileId, int numberOfChunks, Uint8List encryptionKey) async {
    // Stitch the file back together if required
    final encryptedFilePath = await _stitchFileTogether(fileId, numberOfChunks);

    // Decrypt file
    final encryptedFileData =
        await _decryptFileFromDownload(encryptionKey, encryptedFilePath);

    // TODO: Verify file hash

    // Write to output data file
    final decryptedOutputFile = io.File(join(config.dataPath, fileId));
    await decryptedOutputFile.writeAsBytes(encryptedFileData, flush: true);

    // Remove the inbox data
    await io.Directory(join(config.dataInboxPath, fileId))
        .delete(recursive: true);

    await _db.markFileDownloaded(fileId);
  }

  Future<String> _stitchFileTogether(String fileId, int numberOfChunks) async {
    final basePath = join(config.dataInboxPath, fileId);

    // No stitching required
    if (numberOfChunks == 1) {
      return join(basePath, '0');
    }

    final outputFilePath = join(config.dataPath, fileId);
    final outputFile = io.File(outputFilePath);

    for (var chunkIndex = 0; chunkIndex < numberOfChunks; chunkIndex++) {
      final chunkPath = join(basePath, '$chunkIndex');
      final chunkFile = io.File(chunkPath);
      await outputFile.writeAsBytes(await chunkFile.readAsBytes(), flush: true);
    }

    return outputFilePath;
  }

  Future<Uint8List> _decryptFileFromDownload(
      Uint8List encryptionKey, String filePath) async {
    final file = io.File(filePath);
    final data = await file.readAsBytes();

    final decryptedData = await crypto.decryptFile(encryptionKey, data);

    // Was the data compressed?
    if (decryptedData[0] == 0x01) {
      final decompressedData = io.GZipCodec().decode(decryptedData.sublist(1));
      return Uint8List.fromList(decompressedData);
    }

    return decryptedData.sublist(1);
  }

  Future<http.Response> processResponse(String method, String url,
      Map<String, String>? headers, http.Response response) async {
    final log = response.statusCode == io.HttpStatus.ok ? logger.d : logger.e;

    log('${response.statusCode}: $method $url');

    if (headers != null) {
      logger.t(headers);
    }

    if (response.body.isNotEmpty) {
      if (response.headers['content-type'] == 'binary/octet-stream') {
        logger.t('<< Binary data: ${response.contentLength} bytes');
      } else {
        logger.t('<< ${json.encode(response.body)}');
      }
    }

    return response;
  }
}
