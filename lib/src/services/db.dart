import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mutex/mutex.dart';

import 'package:stickerdocs_core/src/services/clock.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/db_schema.dart';
import 'package:stickerdocs_core/src/utils.dart';
import 'package:stickerdocs_core/src/main.dart';

import 'package:stickerdocs_core/src/models/db/block.dart';
import 'package:stickerdocs_core/src/models/db/db_model.dart';
import 'package:stickerdocs_core/src/models/db/block_document.dart';
import 'package:stickerdocs_core/src/models/db/document.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/models/db/shared_sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker.dart';
import 'package:stickerdocs_core/src/models/db/sticker_block_document.dart';
import 'package:stickerdocs_core/src/models/db/sticker_file_document.dart';
import 'package:stickerdocs_core/src/models/db/trusted_user.dart';
import 'package:stickerdocs_core/src/models/db/file_document.dart';
import 'package:stickerdocs_core/src/models/db/invited_user.dart';
import 'package:stickerdocs_core/src/models/event.dart';
import 'package:stickerdocs_core/src/models/file_chunk.dart';

// https://docs.flutter.dev/cookbook/persistence/sqlite

// Reserved SQLite words:
// add all alter and as autoincrement between case check collate commit constraint create default deferrable delete
// distinct drop else escape except exists foreign from group having if in index insert intersect into is isnull join
// limit not notnull null on or order primary references select set table then to transaction union unique update
// using values when where
// - https://pub.dev/packages/sqflite#table-and-column-names

class DBService {
  Database? _dbInstance;
  final ClockService _clock = GetIt.I.get<ClockService>();
  final Mutex syncMutex = Mutex();

  Future<Database> get _db async {
    _dbInstance ??= await _initDb();
    return _dbInstance!;
  }

  Future<Database> _initDb() async {
    // Initialize FFI
    sqfliteFfiInit();

    // Change the default factory
    databaseFactory = databaseFactoryFfi;

    final schema = DBSchema();

    return await openDatabase(config.dbPath,
        version: latestDatabaseVersion,
        onConfigure: _configureDatabase,
        onCreate: schema.create,
        onUpgrade: schema.upgrade);
  }

  Future<void> _configureDatabase(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');

    // https://stackoverflow.com/questions/21668969/whats-the-effective-way-to-compact-sqlite3-db
    // We are not deleting things in general so no need for vacuum
    //await db.execute('PRAGMA auto_vacuum = FULL;');
  }

  Future<void> setConfig(ConfigKey key, String? value) async {
    final db = await _db;

    if (value == null) {
      await db.delete('config', where: 'key = ?', whereArgs: [key.format()]);
      return;
    }

    await db.execute(
        'INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?',
        [key.format(), value, value]);
  }

  Future<String?> getConfig(ConfigKey key) async {
    final db = await _db;

    final result =
        await db.query('config', where: 'key = ?', whereArgs: [key.format()]);

    if (result.isEmpty) {
      return null;
    }

    return result.first['value'].toString();
  }

  Future<void> setAppConfig(String key, String? value) async {
    final db = await _db;
    final formattedKey = 'app.$key';

    if (value == null) {
      await db.delete('config', where: 'key = ?', whereArgs: [formattedKey]);
      return;
    }

    await db.execute(
        'INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?',
        [formattedKey, value, value]);
  }

  Future<String?> getAppConfig(String key) async {
    final db = await _db;
    final formattedKey = 'app.$key';

    final result =
        await db.query('config', where: 'key = ?', whereArgs: [formattedKey]);

    if (result.isEmpty) {
      return null;
    }

    return result.first['value'].toString();
  }

  Future<void> save(DBModel model) async {
    final changes = model.changeset();

    if (changes.isEmpty) {
      return;
    }

    await syncMutex.protect(() async {
      final batch = (await _db).batch();
      final now = await _clock.getTime();

      changes.forEach((key, value) {
        _addEvent(
          batch,
          now,
          latestDatabaseVersion,
          model.table,
          model.id,
          key,
          value,
        );
      });

      await batch.commit(noResult: true);

      // The model events have now been persisted, mark model as not new
      model.isNew = false;

      model.commit();
    });

    await sync();
  }

  Future<void> delete(DBModel model) async {
    await syncMutex.protect(() async {
      final batch = (await _db).batch();
      final now = await _clock.getTime();

      _addEvent(batch, now, latestDatabaseVersion, model.table, model.id,
          dbModelDeleted, isoDateNow());

      await batch.commit(noResult: true);

      // The model events have now been persisted, mark model as not new
      model.isNew = false;

      model.commit();
    });

    await sync();
  }

  void _addEvent(Batch batch, String timestamp, int dbVersion, String type,
      String id, String key, dynamic value,
      {bool isRemote = false}) {
    if (value is DateTime) {
      value = isoDateToString(value);
    } else if (value is bool) {
      value = value ? 1 : 0;
    }

    // TODO: do compression here like we do for files
    // add a compressed flag to the schema also

    // TODO: change event schema: local => processed, remote => uploaded?

    // TODO: consider compressing the value since we are essentially duplicating the data in the DB
    // io.GZipCodec().encode(value);
    // if (value is String){
    //   final compressed = GZipCodec().encode(stringToInt8List(value));
    //   if (compressed.length < value.toString().length) {
    //     value = compressed;
    //     isCompressed = true;
    //   }
    // }

    batch.insert(
        'event',
        {
          'timestamp': timestamp,
          'db_version': dbVersion,
          'type': type,
          'id': id,
          'key': key,
          'value': value,
          'remote': isRemote ? 1 : 0
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Event>> getOutgoingEvents() async {
    final database = await _db;

    await _clock.getTime();

    // Only retrieve non-uploaded events created by this client
    // and ignore any stickerdocs/eventdata files
    final result = await database.query('event',
        columns: [
          'timestamp',
          'db_version',
          'type',
          'id',
          'key',
          'value',
        ],
        where: '''
          remote = 0
          AND timestamp LIKE '%-${_clock.formattedClientId}'
          AND NOT (
            type = 'file' AND id IN
              (
                SELECT file_id
                FROM file
                WHERE content_type = '${CustomContentType.eventData.format()}'
              )
            )
        ''',
        orderBy: 'timestamp');

    return Event.fromMaps(result);
  }

  Future<void> markEventsUploaded(List<Event> outgoingEvents) async {
    final batch = (await _db).batch();

    // Mark outgoing events as uploaded
    for (var event in outgoingEvents) {
      batch.update('event', {'remote': 1},
          where:
              'remote = 0 AND timestamp = ? AND type = ? AND id = ? AND key = ?',
          whereArgs: [
            event.timestamp,
            event.type,
            event.id,
            event.key,
          ]);
    }

    await batch.commit(noResult: true);
  }

  Future<void> applyIncomingEvents(Iterable<Event> events) async {
    final batch = (await _db).batch();

    await syncMutex.protect(() async {
      for (var event in events) {
        _addEvent(
          batch,
          event.timestamp,
          event.dbVersion,
          event.type,
          event.id,
          event.key,
          event.value,
          isRemote: true,
        );
      }

      await batch.commit(noResult: true);
    });

    await sync();
  }

  // Update the DB based off the state changes
  Future<void> sync() async {
    await syncMutex.protect(() async {
      await _sync();
    });
  }

  Future<void> _sync() async {
    final db = await _db;

    // Get a batch of events to process
    final newEvents = await db.query('event',
        where: 'local = 0 AND db_version <= ?',
        whereArgs: [latestDatabaseVersion]);

    if (newEvents.isEmpty) {
      return;
    }

    // get a mapping of table name to unique IDs
    final tablesAndIds = getTableNamesAndUniqueIds(newEvents);

    final batch = db.batch();

    for (var tableName in tablesAndIds.keys) {
      var idsToCreate = tablesAndIds[tableName]!;
      var existingEventsQuery =
          DBSchema.getExistingEventsQuery(tableName, idsToCreate);
      var existingEvents = await db.rawQuery(existingEventsQuery);

      final uniqueExistingIds =
          existingEvents.map((event) => event['id']).toSet();

      // Remove existing Ids from this list
      idsToCreate.removeWhere((id) => uniqueExistingIds.contains(id));

      // Create any new DB records
      if (idsToCreate.isNotEmpty) {
        var insertIdInQuery = '(\'${idsToCreate.join('\'),(\'')}\')';
        batch.rawInsert(
            'INSERT INTO $tableName (${tableName}_id) VALUES $insertIdInQuery');
      }

      // Update DB from events
      for (var event
          in newEvents.where((event) => event['type'] == tableName)) {
        bool ignore = false;

        // Is there an existing event for this id + key?
        var existingEvent = existingEvents.where((existingEvent) =>
            existingEvent['id'] == event['id'] &&
            existingEvent['key'] == event['key']);

        // If so if the existing timestamp is newer then ignore
        if (existingEvent.isNotEmpty) {
          if (_clock.isBNewer(event['timestamp'].toString(),
              existingEvent.first['timestamp'].toString())) {
            ignore = true;
          }
        }

        if (!ignore) {
          var val = event['value'];

          batch.update(
            event['type'].toString(),
            {event['key'].toString(): val},
            where: '${event['type']}_id = ?',
            whereArgs: [event['id'].toString()],
          );
        }

        // Mark event processed
        batch.update(
          'event',
          {'local': 1},
          where: 'timestamp = ? AND type = ? AND id = ? AND key = ?',
          whereArgs: [
            event['timestamp'],
            event['type'],
            event['id'],
            event['key']
          ],
        );
      }
    }

    await batch.commit(noResult: true);
  }

  static String formatInQuery(Iterable<String> ids) {
    return 'IN (\'${ids.join('\',\'')}\')';
  }

  Map<String, List<String>> getTableNamesAndUniqueIds(
      List<Map<String, Object?>> events) {
    Map<String, List<String>> map = <String, List<String>>{};

    for (var element in events) {
      String type = element['type'] as String;
      String id = element['id'] as String;

      if (!map.containsKey(type)) {
        map[type] = <String>[id];
      } else {
        if (!map[type]!.contains(id)) {
          map[type]!.add(id);
        }
      }
    }

    return map;
  }

  Future<void> addFileChunkUploadEntries(List<FileChunk> fileChunks) async {
    final batch = (await _db).batch();

    for (var fileChunk in fileChunks) {
      batch.insert('file_chunk_upload', {
        'file_id': fileChunk.fileId,
        'chunk_index': fileChunk.index,
        'md5': fileChunk.md5,
        'size': fileChunk.size
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> addFileChunkDownloadEntries(
      List<FileChunk> fileChunks, String? sourceUserId) async {
    final batch = (await _db).batch();

    for (var fileChunk in fileChunks) {
      batch.insert('file_chunk_download', {
        'file_id': fileChunk.fileId,
        'chunk_index': fileChunk.index,
        'source_user_id': sourceUserId,
        'md5': fileChunk.md5,
        'url': fileChunk.url,
        'url_created': isoDateToString(fileChunk.urlCreated!),
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> updateFileChunkUploadUrls(List<FileChunk> fileChunks) async {
    final batch = (await _db).batch();

    for (var fileChunk in fileChunks) {
      batch.update(
          'file_chunk_upload',
          {
            'url': fileChunk.url,
            'url_created': isoDateToString(fileChunk.urlCreated!)
          },
          where: 'file_id = ? AND chunk_index = ?',
          whereArgs: [fileChunk.fileId, fileChunk.index]);
    }

    await batch.commit(noResult: true);
  }

  Future<List<FileChunk>> getFileChunksForUpload(String fileId) async {
    final db = await _db;

    // Do not filter by AND uploaded = 0 here
    // This is because we need to know whether the file has been chunked or not
    // If we do that filter then we might try to re-encrypt the file

    final result = await db.query(
      'file_chunk_upload',
      where: 'file_id = ?',
      whereArgs: [fileId],
      orderBy: 'chunk_index',
    );

    return FileChunk.fromMaps(result);
  }

  Future<List<FileChunk>> getFileChunksForDownload(String fileId) async {
    final db = await _db;

    // Do not filter by AND uploaded = 0 here
    // This is because we need to know whether the file has been chunked or not
    // If we do that filter then we will try to re-decrypt the file

    final result = await db.query(
      'file_chunk_download',
      where: 'not_found = 0 AND file_id = ?',
      whereArgs: [fileId],
      orderBy: 'chunk_index',
    );

    return FileChunk.fromMaps(result);
  }

  Future<void> markFileNotFound(String fileId) async {
    final db = await _db;

    await db.update(
      'file',
      {
        'not_found': 1,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  Future<void> incrementFileChunkUploadCounter(FileChunk fileChunk) async {
    final db = await _db;

    await db.rawUpdate(
        'UPDATE file_chunk_upload SET attempt = attempt + 1 WHERE file_id = \'${fileChunk.fileId}\' AND chunk_index = ${fileChunk.index}');
  }

  Future<void> markFileChunkUploaded(FileChunk fileChunk) async {
    final db = await _db;

    await db.update('file_chunk_upload', {'uploaded': 1},
        where: 'file_id = ? AND chunk_index = ? AND uploaded = 0',
        whereArgs: [fileChunk.fileId, fileChunk.index]);
  }

  Future<void> updateFileChunkDownloadUrl(FileChunk fileChunk) async {
    final db = await _db;

    await db.update(
      'file_chunk_download',
      {
        'url': fileChunk.url,
        'url_created': isoDateToString(fileChunk.urlCreated!),
      },
      where: 'file_id = ? AND chunk_index = ?',
      whereArgs: [fileChunk.fileId, fileChunk.index],
    );
  }

  Future<void> markFileChunkDownloadNotFound(FileChunk fileChunk) async {
    final db = await _db;

    // If any chunk cannot be downloaded consider the whole file gone
    await db.delete('file_chunk_download',
        where: 'file_id = ?', whereArgs: [fileChunk.fileId]);

    await markFileNotFound(fileChunk.fileId);
  }

  Future<void> incrementFileChunkDownloadCounter(FileChunk fileChunk) async {
    final db = await _db;

    await db.rawUpdate(
        'UPDATE file_chunk_download SET attempt = attempt + 1 WHERE file_id = \'${fileChunk.fileId}\' AND chunk_index = ${fileChunk.index}');
  }

  Future<void> markFileChunkDownloaded(FileChunk fileChunk) async {
    final db = await _db;

    await db.update(
      'file_chunk_download',
      {'downloaded': 1},
      where: 'file_id = ? AND chunk_index = ? AND downloaded = 0',
      whereArgs: [fileChunk.fileId, fileChunk.index],
    );
  }

  Future<void> markFileDownloaded(String fileId) async {
    final batch = (await _db).batch();

    batch.update(
      'file',
      {'downloaded': 1},
      where: 'file_id = ? AND downloaded = 0',
      whereArgs: [fileId],
    );

    batch.delete('file_chunk_download',
        where: 'file_id = ?', whereArgs: [fileId]);

    await batch.commit(noResult: true);
  }

  Future<void> markFileUploaded(String fileId) async {
    final batch = (await _db).batch();

    batch.update('file', {'uploaded': 1},
        where: 'file_id = ? AND uploaded = 0', whereArgs: [fileId]);

    batch
        .delete('file_chunk_upload', where: 'file_id = ?', whereArgs: [fileId]);

    await batch.commit(noResult: true);
  }

  Future<List<File>> getFilesToUpload() async {
    final db = await _db;

    final result = await db.query('file',
        where: 'uploaded = 0 AND downloaded = 0 AND deleted IS NULL');

    return File.fromMaps(result);
  }

  Future<List<File>> getFilesToDownload() async {
    final db = await _db;

    final result = await db.query('file',
        where:
            'uploaded = 0 AND downloaded = 0 AND not_found = 0 AND deleted IS NULL AND encryption_key IS NOT NULL');

    return File.fromMaps(result);
  }

  Future<List<File>> getPurgeableFiles() async {
    final db = await _db;

    final result = await db.query('file',
        where:
            '(uploaded = 1 OR downloaded = 1) AND deleted IS NULL AND encryption_key IS NOT NULL');

    return File.fromMaps(result);
  }

  Future<void> markFileAsNotDownloaded(File file) async {
    final db = await _db;

    await db.update(
        'file',
        {
          'downloaded': 0,
          'uploaded': 0,
        },
        where: 'file_id = ?',
        whereArgs: [file.id]);
  }

  Future<void> cleanupSyncFilesAndEvents() async {
    final batch = (await _db).batch();

    batch.delete('file',
        where:
            'content_type = \'${CustomContentType.eventData.format()}\' AND uploaded = 1');

    batch.delete('event', where: '''
      type = 'file'
      AND id IN (
        SELECT id
        FROM event
        WHERE type = 'file'
        AND key = 'content_type'
        AND value = '${CustomContentType.eventData.format()}'
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> deleteFile(File file) async {
    await delete(file);

    final batch = (await _db).batch();

    batch.delete('file_chunk_upload',
        where: 'file_id = ?', whereArgs: [file.id]);
    batch.delete('file_chunk_download',
        where: 'file_id = ?', whereArgs: [file.id]);
    batch.update(
        'file',
        {
          'downloaded': 0,
          'uploaded': 0,
        },
        where: 'file_id = ?',
        whereArgs: [file.id]);

    await batch.commit(noResult: true);
  }

  Future<File?> getFileBySignature(int size, String sha256) async {
    final db = await _db;

    final result = await db.query('file',
        where: 'size = ? AND sha256 = ? AND deleted IS NULL',
        whereArgs: [size, sha256]);

    if (result.isEmpty) {
      return null;
    }

    return File.fromMap(result.single);
  }

  Future<File?> getFileById(String fileId) async {
    final db = await _db;

    final result = await db.query('file',
        where: 'file_id = ? AND deleted IS NULL', whereArgs: [fileId]);
    if (result.isEmpty) {
      return null;
    }
    return File.fromMap(result.single);
  }

  Future<List<Block>> getBlocksForBlockDocument(
      BlockDocument blockDocument) async {
    final db = await _db;

    final blockIds = blockDocument.getBlockIds();

    final result = await db.rawQuery('''
      SELECT *
      FROM block
      WHERE block_id ${formatInQuery(blockIds)}
      AND deleted IS NULL
    ''');

    // Re order the blocks as they will come from the DB in unpredictable order
    final blocks = List<Block>.filled(
        blockDocument.blocks!.length, Block(type: BlockType.file));

    for (final row in result) {
      final block = Block.fromMap(row);
      blocks[blockIds.indexOf(block.id)] = block;
    }

    return blocks;
  }

  Future<Iterable<String>> getAllFileIds() async {
    final db = await _db;

    final result = await db.query(
      'file',
      columns: ['file_id'],
      where: 'deleted IS NULL',
    );

    return result.map((file) => file['file_id'].toString());
  }

  Future<int> countAllDocuments() async {
    final db = await _db;

    final fileDocumentCount = await db.rawQuery(
        'SELECT COUNT(*) count FROM file_document WHERE deleted IS NULL');

    final blockDocumentCount = await db.rawQuery(
        'SELECT COUNT(*) count FROM block_document WHERE deleted IS NULL');

    return (int.tryParse(fileDocumentCount.first['count'].toString()) ?? 0) +
        (int.tryParse(blockDocumentCount.first['count'].toString()) ?? 0);
  }

  Future<List<Document>> searchDocuments(String? query) async {
    final documents = <Document>[];
    final db = await _db;

    final formattedQuery = query ?? '';
    final titleQuery = formattedQuery.isEmpty ? '' : 'AND title LIKE ?';

    final fileDocuments = await db.query('file_document',
        where: 'deleted IS NULL $titleQuery',
        whereArgs: formattedQuery.isEmpty ? null : ['%$query%'],
        orderBy: 'updated DESC');

    documents.addAll(FileDocument.fromMaps(fileDocuments));

    final blockDocuments = await db.query('block_document',
        where: 'deleted IS NULL $titleQuery',
        whereArgs: formattedQuery.isEmpty ? null : ['%$query%'],
        orderBy: 'updated DESC');

    documents.addAll(BlockDocument.fromMaps(blockDocuments));

    return documents;
  }

  Future<int> countAllStickers() async {
    final db = await _db;

    final stickerCount = await db
        .rawQuery('SELECT COUNT(*) count FROM sticker WHERE deleted IS NULL');

    return int.tryParse(stickerCount.first['count'].toString()) ?? 0;
  }

  Future<List<Sticker>> searchStickers(String? query) async {
    final db = await _db;

    final formattedQuery = query ?? '';
    final titleQuery = formattedQuery.isEmpty ? '' : 'AND name LIKE ?';

    final result = await db.query('sticker',
        where: 'deleted IS NULL $titleQuery',
        whereArgs: formattedQuery.isEmpty ? null : ['%$query%'],
        orderBy: 'updated DESC');

    return Sticker.fromMaps(result);
  }

  Future<List<Sticker>> getDocumentStickers(Document document) async {
    final stickers = <Sticker>[];
    final db = await _db;

    if (document is FileDocument) {
      final result = await db.rawQuery('''
        SELECT s.*
        FROM sticker s
        JOIN sticker_file_document sfd ON sfd.sticker_id = s.sticker_id
        WHERE sfd.file_document_id = '${document.id}'
        AND s.deleted IS NULL
        AND sfd.deleted IS NULL
        ORDER BY sfd.created
      ''');

      stickers.addAll(Sticker.fromMaps(result));
    }

    if (document is BlockDocument) {
      final result = await db.rawQuery('''
        SELECT s.*
        FROM sticker s
        JOIN sticker_block_document sbd ON sbd.sticker_id = s.sticker_id
        WHERE sbd.block_document_id == '${document.id}'
        AND s.deleted IS NULL
        AND sbd.deleted IS NULL
        ORDER BY sbd.created DESC
      ''');

      stickers.addAll(Sticker.fromMaps(result));
    }

    return stickers;
  }

  Future<Sticker?> getStickerByName(String name) async {
    final db = await _db;

    final result =
        await db.query('sticker', where: 'name = ?', whereArgs: [name]);

    if (result.length != 1) {
      return null;
    }

    return Sticker.fromMap(result.single);
  }

  Future<Sticker?> getStickerById(String id) async {
    final db = await _db;

    final result = await db.query('sticker',
        where: 'sticker_id = ? AND deleted IS NULL', whereArgs: [id]);

    if (result.length != 1) {
      return null;
    }

    return Sticker.fromMap(result.single);
  }

  Future<List<FileDocument>> getFileDocumentsLabelledWithStickerId(
      String stickerId) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT fd.*
      FROM file_document fd
      JOIN sticker_file_document sfd ON sfd.file_document_id = fd.file_document_id
      WHERE sfd.sticker_id = '$stickerId'
      AND fd.deleted IS NULL
      AND sfd.deleted IS NULL
    ''');

    return FileDocument.fromMaps(result);
  }

  Future<List<StickerBlockDocument>>
      getStickerBlockDocumentsLabelledWithStickerIds(
          List<String> stickerIds) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT *
      FROM sticker_block_document
      WHERE sticker_id ${formatInQuery(stickerIds)}
      AND deleted IS NULL
    ''');

    return StickerBlockDocument.fromMaps(result);
  }

  Future<List<File>>
      getFilesLabelledWithStickerWhichHaveNotBeenEncryptedForThatSticker(
          Sticker sticker) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT f.*
      FROM file f      
      JOIN file_document fd ON fd.file_id = f.file_id
      JOIN sticker_file_document sfd ON sfd.file_document_id = fd.file_document_id
      WHERE sfd.sticker_id = '${sticker.id}'
      AND f.deleted IS NULL
      AND fd.deleted IS NULL
      AND sfd.deleted IS NULL
      AND f.encryption_key IS NOT NULL
      AND f.file_id NOT IN (
        SELECT file_id
        FROM sticker_shared_file
        WHERE sticker_id = '${sticker.id}'
        AND deleted IS NULL
      )
    ''');

    return File.fromMaps(result);
  }

  Future<List<File>> getSharedFilesLabelledWithStickerId(
      String stickerId, TrustedUser sharedWith) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT f.*
      FROM file f      
      JOIN shared_object so ON so.type = '${File.tableName}' AND so.object_id = f.file_id
      JOIN file_document fd ON fd.file_id = f.file_id
      JOIN sticker_file_document sfd ON sfd.file_document_id = fd.file_document_id
      WHERE sfd.sticker_id = '$stickerId'
      AND so.trusted_user_id = '${sharedWith.id}'
      AND so.deleted IS NULL
    ''');

    return File.fromMaps(result);
  }

  Future<List<InvitedUser>> getInvitations() async {
    final db = await _db;

    final result = await db.query('invitation', where: 'deleted IS NULL');

    return InvitedUser.fromMaps(result);
  }

  Future<List<TrustedUser>> getTrustedUsers() async {
    final db = await _db;

    final result = await db.query('trusted_user', where: 'deleted IS NULL');

    return TrustedUser.fromMaps(result);
  }

  Future<FileDocument?> getFileDocumentByFileId(String fileId) async {
    final db = await _db;

    final result = await db.query('file_document',
        where: 'deleted IS NULL AND file_id = ?', whereArgs: [fileId]);

    if (result.isEmpty) {
      return null;
    }

    return FileDocument.fromMap(result.single);
  }

  Future<FileDocument?> getFileDocumentById(String fileDocumentId) async {
    final db = await _db;

    final result = await db
        .query('file_document', where: 'id = ?', whereArgs: [fileDocumentId]);

    if (result.isEmpty) {
      return null;
    }

    return FileDocument.fromMap(result.single);
  }

  Future<StickerFileDocument?> getStickerFileDocument(
      Sticker sticker, FileDocument fileDocument) async {
    final db = await _db;

    final result = await db.query('sticker_file_document',
        where: 'deleted IS NULL AND sticker_id = ? AND file_document_id = ?',
        whereArgs: [sticker.id, fileDocument.id]);

    if (result.isEmpty) {
      return null;
    }

    return StickerFileDocument.fromMap(result.single);
  }

  Future<StickerFileDocument?> getStickerFileDocumentFromIds(
      String stickerId, String fileDocumentId) async {
    final db = await _db;

    final result = await db.query('sticker_file_document',
        where: 'deleted IS NULL AND sticker_id = ? AND file_document_id = ?',
        whereArgs: [stickerId, fileDocumentId]);

    if (result.isEmpty) {
      return null;
    }

    return StickerFileDocument.fromMap(result.single);
  }

  Future<StickerFileDocument?> getStickerFileDocumentById(
      String stickerFileDocumentId) async {
    final db = await _db;

    final result = await db.query('sticker_file_document',
        where: 'id = ?', whereArgs: [stickerFileDocumentId]);

    if (result.isEmpty) {
      return null;
    }

    return StickerFileDocument.fromMap(result.single);
  }

  Future<StickerBlockDocument?> getStickerBlockDocumentFromIds(
      String stickerId, String blockDocumentId) async {
    final db = await _db;

    final result = await db.query('sticker_block_document',
        where: 'deleted IS NULL AND sticker_id = ? AND block_document_id = ?',
        whereArgs: [stickerId, blockDocumentId]);

    if (result.isEmpty) {
      return null;
    }

    return StickerBlockDocument.fromMap(result.single);
  }

  Future<bool> isSharedObject(
      String type, String id, String trustedUserId) async {
    final db = await _db;

    final result = await db.query('shared_object',
        where:
            'deleted IS NULL AND type = ? AND object_id = ? AND trusted_user_id = ?',
        whereArgs: [type, id, trustedUserId]);

    return result.isNotEmpty;
  }

  Future<StickerBlockDocument?> getStickerBlockDocument(
      Sticker sticker, BlockDocument blockDocument) async {
    final db = await _db;

    final result = await db.query('sticker_block_document',
        where: 'deleted IS NULL AND sticker_id = ? AND block_document_id = ?',
        whereArgs: [sticker.id, blockDocument.id]);

    if (result.isEmpty) {
      return null;
    }

    return StickerBlockDocument.fromMap(result.single);
  }

  Future<List<SharedSticker>> getSharedStickers() async {
    final db = await _db;
    final result = await db.query('shared_sticker', where: 'deleted IS NULL');

    return SharedSticker.fromMaps(result);
  }

  Future<List<Event>> getStickerSnapshotEvents(String stickerId) async {
    return await getEventSnapshot('sticker', stickerId);
  }

  Future<List<Event>> getFileSnapshotEvents(String fileId) async {
    return await getEventSnapshot('file', fileId);
  }

  Future<List<Event>> getBlockDocumentSnapshotEvents(
      String blockDocumentId) async {
    return await getEventSnapshot('block_document', blockDocumentId);
  }

  Future<List<Event>> getBlockSnapshotEvents(String blockId) async {
    return await getEventSnapshot('block', blockId);
  }

  Future<List<Event>> getStickerFileDocumentSnapshotEvents(
      String stickerFileDocumentId) async {
    return await getEventSnapshot(
        'sticker_file_document', stickerFileDocumentId);
  }

  Future<List<Event>> getStickerBlockDocumentSnapshotEvents(
      String stickerBlockDocumentId) async {
    return await getEventSnapshot(
        'sticker_block_document', stickerBlockDocumentId);
  }

  Future<List<Event>> getFileDocumentSnapshotEvents(
      String fileDocumentId) async {
    return await getEventSnapshot('file_document', fileDocumentId);
  }

  Future<List<Event>> getEventSnapshot(String eventType, String eventId) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT x.*
      FROM (
          SELECT *
          FROM event
          WHERE type = '$eventType'
          AND id = '$eventId'
          ORDER BY timestamp DESC
      ) AS x
      WHERE NOT EXISTS (
        SELECT  1
        FROM    event AS e
        WHERE   e.type = x.type
        AND     e.id = x.id
        AND     e.key = 'deleted'
      )
      GROUP BY x.id, x.key
    ''');

    return Event.fromMaps(result);
  }

  Future<TrustedUser?> getTrustedUserByUserId(String userId) async {
    final db = await _db;

    final result = await db.query('trusted_user',
        where: 'user_id = ? AND deleted IS NULL', whereArgs: [userId]);

    if (result.isEmpty) {
      return null;
    }

    return TrustedUser.fromMap(result.first);
  }

  Future<void> close() async {
    if (_dbInstance == null) {
      return;
    }

    await _dbInstance!.close();
    _dbInstance = null;
    databaseFactoryOrNull =
        null; // https://stackoverflow.com/questions/76233907/sqflite-flutter-warning
  }

  Future<bool> hasDocumentBeenShared(Document document) async {
    final db = await _db;

    if (document is FileDocument) {
      final result = await db.rawQuery('''
        SELECT f.source_user_id
        FROM file f
        JOIN file_document fd ON fd.file_id = f.file_id
        WHERE fd.file_document_id = '${document.id}'
        AND fd.deleted IS NULL
        AND f.deleted IS NULL
      ''');

      return result.first['source_user_id'] != null;
    }

    return false;
  }

  Future<String?> getInitialEncryptionKeyForFile(File file) async {
    final db = await _db;

    final result = await db.query(
      'event',
      columns: ['value'],
      where: 'type = ? AND id = ? AND key = ?',
      whereArgs: [file.table, file.id, File.encryptionKeyKey],
      orderBy: 'timestamp',
      limit: 1,
    );

    if (result.length != 1) {
      return null;
    }

    return result.first['value'].toString();
  }
}
