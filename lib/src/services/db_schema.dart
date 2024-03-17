import 'package:sqflite/sqflite.dart';

// Version is stored in 'PRAGMA user_version'
const latestDatabaseVersion = 1;

class DBSchema {
  Future<void> create(Database db, int version) async {
    var batch = db.batch();
    _createConfigTableV1(batch);
    _createEventTableV1(batch);
    _createFileTableV1(batch);
    _createFileChunkUploadTableV1(batch);
    _createFileChunkDownloadTableV1(batch);
    _createFileDocumentTableV1(batch);
    _createBlockTableV1(batch);
    _createBlockDocumentTableV1(batch);
    _createStickerTableV1(batch);
    _createStickerFileDocumentTableV1(batch);
    _createStickerBlockDocumentTableV1(batch);
    _createTrustRequestTableV1(batch);
    _createTrustedUserTableV1(batch);
    _createSharedStickerTableV1(batch);
    _createSharedObjectsTableV1(batch);

    await batch.commit(noResult: true);
  }

  Future<void> upgrade(Database db, int oldVersion, int newVersion) async {
    var batch = db.batch();

    if (oldVersion == 1) {
      // TODO: implement when we have migrations to perform
    }

    await batch.commit(noResult: true);
  }

  void _createConfigTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE config (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    batch.execute(
        'INSERT INTO config (key, value) VALUES (\'firstRun\', \'true\')');
  }

  void _createEventTableV1(Batch batch) {
    // https://www.youtube.com/watch?v=iEFcmfmdh2w
    // - James Long
    batch.execute('''
      CREATE TABLE event (
        timestamp TEXT NOT NULL,
        db_version INT NOT NULL,
        type TEXT NOT NULL,
        id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT,
        local INT NOT NULL DEFAULT 0,
        remote INT NOT NULL DEFAULT 0,
        PRIMARY KEY(timestamp, type, id, key)
      )''');
  }

  // synchronizable model object
  void _createFileTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE file (
        file_id TEXT UNIQUE PRIMARY KEY,
        source_user_id TEXT,
        name TEXT,
        size INTEGER,
        sha256 TEXT,
        content_type TEXT,
        uploaded int DEFAULT 0 NOT NULL,
        downloaded int DEFAULT 0 NOT NULL,
        encryption_key TEXT,
        created TEXT,
        updated TEXT,
        deleted TEXT
      )''');
  }

  void _createFileChunkUploadTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE file_chunk_upload (
        file_id TEXT NOT NULL,
        chunk_index INT NOT NULL,
        md5 TEXT NOT NULL,
        size INT,
        url TEXT,
        url_created TEXT,
        attempt INT DEFAULT 0 NOT NULL,
        uploaded int DEFAULT 0 NOT NULL,
        PRIMARY KEY(file_id, chunk_index),
        FOREIGN KEY(file_id) REFERENCES file(file_id)
      )''');
  }

  void _createFileChunkDownloadTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE file_chunk_download (
        file_id TEXT NOT NULL,
        chunk_index INT NOT NULL,
        source_user_id TEXT,
        md5 TEXT NOT NULL,
        url TEXT,
        url_created TEXT,
        attempt INT DEFAULT 0 NOT NULL,
        downloaded int DEFAULT 0 NOT NULL,
        PRIMARY KEY(file_id, chunk_index)
      )''');
  }

  // synchronizable model object
  void _createFileDocumentTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE file_document (
        file_document_id TEXT UNIQUE PRIMARY KEY,
        file_id TEXT,
        title TEXT,
        created TEXT,
        updated TEXT,
        deleted TEXT,
        FOREIGN KEY(file_id) REFERENCES file(file_id)
      )''');
  }

  // synchronizable model object
  void _createBlockTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE block (
        block_id TEXT UNIQUE PRIMARY KEY,
        type TEXT,
        data TEXT,
        created TEXT,
        updated TEXT,
        deleted TEXT
      )''');
  }

  // synchronizable model object
  void _createBlockDocumentTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE block_document (
        block_document_id TEXT UNIQUE PRIMARY KEY,
        title TEXT,
        blocks TEXT,
        created TEXT,
        updated TEXT,
        deleted TEXT
      )''');
  }

  // synchronizable model object
  void _createStickerTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE sticker (
        sticker_id TEXT UNIQUE PRIMARY KEY,
        name TEXT,
        style TEXT,
        svg TEXT,
        created TEXT,
        updated TEXT,
        deleted TEXT
      )''');
  }

  // synchronizable model object
  void _createStickerFileDocumentTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE sticker_file_document (
        sticker_file_document_id TEXT UNIQUE PRIMARY KEY,
        sticker_id TEXT,
        file_document_id TEXT,
        created TEXT,
        deleted TEXT,
        FOREIGN KEY(sticker_id) REFERENCES sticker(sticker_id),
        FOREIGN KEY(file_document_id) REFERENCES file_document(file_document_id)
      )''');
  }

  // synchronizable model object
  void _createStickerBlockDocumentTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE sticker_block_document (
        sticker_block_document_id TEXT UNIQUE PRIMARY KEY,
        sticker_id TEXT,
        block_document_id TEXT,
        created TEXT,
        deleted TEXT,
        FOREIGN KEY(sticker_id) REFERENCES sticker(sticker_id),
        FOREIGN KEY(block_document_id) REFERENCES block_document(block_document_id)
      )''');
  }

  // synchronizable model object
  void _createTrustRequestTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE invitation (
        invitation_id TEXT UNIQUE PRIMARY KEY,
        sticker_id TEXT,
        name TEXT,
        email TEXT,
        signing_public_key TEXT,
        signing_private_key TEXT,
        created TEXT,
        deleted TEXT,
        FOREIGN KEY(sticker_id) REFERENCES sticker(sticker_id)
      )''');
  }

  // synchronizable model object
  void _createTrustedUserTableV1(Batch batch) {
    batch.execute('''CREATE TABLE trusted_user (
      trusted_user_id TEXT UNIQUE PRIMARY KEY,
      user_id TEXT,
      name TEXT,
      email TEXT,
      public_key TEXT,
      created TEXT,
      updated TEXT,
      deleted TEXT
    )''');
  }

  // synchronizable model object
  void _createSharedStickerTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE shared_sticker (
        shared_sticker_id TEXT UNIQUE PRIMARY KEY,
        sticker_id TEXT,
        trusted_user_id TEXT,
        shared_by_me INT,
        ignore_external_events INT,
        created TEXT,
        deleted TEXT,
        FOREIGN KEY(sticker_id) REFERENCES sticker(sticker_id),
        FOREIGN KEY(trusted_user_id) REFERENCES trusted_user(trusted_user_id)
      )''');
  }

  void _createSharedObjectsTableV1(Batch batch) {
    batch.execute('''
      CREATE TABLE shared_object (
        shared_object_id TEXT UNIQUE PRIMARY KEY,
        type TEXT,
        object_id TEXT,
        trusted_user_id TEXT,
        created TEXT,
        deleted TEXT,
        FOREIGN KEY(trusted_user_id) REFERENCES trusted_user(trusted_user_id)
      )''');
  }

  static String getExistingEventsQuery(String tableName, List<String> ids) {
    final idInQuery = '\'${ids.join('\',\'')}\'';

    return '''
      SELECT
        timestamp,
        type,
        id,
        key
      FROM (
        SELECT
          timestamp,
          type,
          id,
          key,
          ROW_NUMBER() OVER (
            PARTITION BY type, id, key
            ORDER BY timestamp DESC
          ) row
        FROM event
        WHERE
          type = '$tableName'
          AND id IN ($idInQuery)
          AND local = 1
      )
      WHERE row = 1''';
  }
}
