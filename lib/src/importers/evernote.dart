import 'dart:convert';
import 'dart:io' as io;
import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/models/db/block_document.dart';
import 'package:stickerdocs_core/src/models/db/block.dart';
import 'package:stickerdocs_core/src/models/db/file.dart';
import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/utils.dart';
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

// All top-level EN XML tags (not looking inside CDATA):
// alternate-data
// altitude
// application-data
// attachment
// author
// camera-make
// camera-model
// content
// content-class
// created
// creator
// data
// dueDate
// dueDateUIOption
// duration
// en-export
// file-name
// height
// lastEditor
// latitude
// longitude
// mime
// note
// note-attributes
// noteLevelID
// reco-type
// recognition
// reminder-done-time
// reminder-order
// reminder-time
// repeatAfterCompletion
// resource
// resource-attributes
// sortWeight
// source
// source-application
// source-url
// statusUpdated
// subject-date
// tag
// task
// taskFlag
// taskGroupNoteLevelID
// taskStatus
// timeZone
// timestamp
// title
// updated
// width

// All EN CDATA tags:
// a,abbr,address,area,b,big,blockquote,br,center,cite,code,col,colgroup,dd,div,dl,dt,em,en-media,en-note,en-todo,font,h1,h2,h3,h4,h5,h6,hr,i,img,ins,kbd,li,map,ol,p,pre,s,small,span,strike,strong,sub,sup,table,tbody,td,th,thead,tr,u,ul

// HMMM so what about this then!?!:

// Note:
// <div><en-todo checked='true'/>task</div>

// TODO:
// Made someone’s life good/better -> Made someoneâ&#x80;&#x99;s life good/better
// Probably due to uint8ListToString, encoding should be utf-8

class EvernoteImporter {
  final AppLogic logic;

  EvernoteImporter(this.logic);

  Future<void> import(io.File file) async {
    final notes = await file
        .openRead()
        .transform(utf8.decoder)
        .toXmlEvents()
        .normalizeEvents()
        .selectSubtreeEvents(_selectNoteEvents)
        .toXmlNodes()
        .toList();

    for (final note in notes) {
      //?
      for (final x in note) {
        await _importNote(x as XmlElement);
      }
    }
  }

  bool _selectNoteEvents(event) =>
      event.nodeType == XmlNodeType.ELEMENT && event.name == 'note';

  Future<void> _importNote(XmlElement noteElement) async {
    final Map<String, String> md5ToSha256Mappings = {};
    final Map<String, String> sha256ToFileIdMappings = {};
    final noteTitle = noteElement.getElement('title')!.innerText;

    logger.i('Importing note: $noteTitle');

    final files = await _getFiles(
        md5ToSha256Mappings, sha256ToFileIdMappings, noteElement);

    List<Block> additionalBlocks = [];
    final contentElement = noteElement.getElement('content');

    if (contentElement != null) {
      additionalBlocks = await _processNoteContent(noteTitle, contentElement,
          files, md5ToSha256Mappings, sha256ToFileIdMappings);
    } else {
      logger.i('No note content');
    }

    final noteFile = await _saveNoteXml(noteElement, noteTitle);
    final evernoteFileBlock = Block(type: BlockType.evernoteData);
    evernoteFileBlock.data = noteFile.id;

    // The first block is the raw 'enex' file, stripped of file data
    // and wth the MD5 hashes replace with sha256 hashes
    final blocks = <Block>[evernoteFileBlock];

    // Followed by the other blocks
    blocks.addAll(additionalBlocks);

    // Save the blocks
    for (final block in blocks) {
      await logic.saveBlock(block);
    }

    // Save the block document
    final blockDocument = BlockDocument();
    blockDocument.title = noteTitle;
    blockDocument.blocks = blocks.map((block) => block.id).toList().join(',');
    await logic.saveBlockDocument(blockDocument);

    // TODO: make this work - stickers cannot exist without SVGs
    //await _attachStickers(noteElement, blockDocument);
  }

  Future<File> _saveNoteXml(XmlElement noteElement, String? noteTitle) async {
    final noteFile = await logic.createOrGetExistingFileFromBytes(
        stringToUint8List(noteElement.innerXml), '$noteTitle.enex');

    await logic.saveFile(noteFile);
    return noteFile;
  }

  Future<List<File?>> _getFiles(
      Map<String, String> md5ToSha256Mappings,
      Map<String, String> sha256ToFileIdMappings,
      XmlElement noteElement) async {
    final resourceElements = noteElement.findAllElements('resource');

    final List<File?> files = [];

    for (final resource in resourceElements) {
      files.add(await _processNoteResource(
          md5ToSha256Mappings, sha256ToFileIdMappings, resource));
    }
    return files;
  }

  Future<void> _attachStickers(
      XmlElement noteElement, BlockDocument blockDocument) async {
    for (final tag in noteElement.findElements('tag').map((e) => e.innerText)) {
      final sticker = await logic.getOrCreateSticker(tag);
      await logic.attachStickerToDocument(blockDocument, sticker);
    }
  }

  // Example:
  // <resource-attributes>
  //   <file-name>Snapshot.png</file-name>
  //   <source-url>
  //     en-cache://tokenKey%3D%22AuthToken%3AUser%3A211722314%22+b0f7004d-941a-fcb2-79be-ac49bab7c162+7d0f755ab70997975acdba504c510ea0+https://www.evernote.com/shard/s363/res/4bb96418-58a8-4797-9884-583f2f518e0e
  //   </source-url>
  // </resource-attributes>
  Future<File?> _processNoteResource(
      Map<String, String> md5ToSha256Mappings,
      Map<String, String> sha256ToFileIdMappings,
      XmlElement resourceElement) async {
    final resourceAttributesElement =
        resourceElement.getElement('resource-attributes');

    String? fileName;

    if (resourceAttributesElement != null) {
      fileName =
          _getFileNameFromResourceAttributesElement(resourceAttributesElement);
    }

    final dataElement = resourceElement.getElement('data');

    if (dataElement == null || dataElement.innerText.isEmpty) {
      logger.w('No data');
      return null;
    }

    final encoding = dataElement.getAttribute('encoding');

    if (encoding == null || encoding != 'base64') {
      logger.w('Unexpected encoding: \'$encoding\'');
      return null;
    }

    final fileData =
        base64Decode(dataElement.innerText.trim().replaceAll('\n', ''));

    final file =
        await logic.createOrGetExistingFileFromBytes(fileData, fileName);

    await logic.saveFile(file);

    md5ToSha256Mappings[CryptoService.md5(fileData)] = file.sha256!;
    sha256ToFileIdMappings[file.sha256!] = file.id;

    // Remove the data from the resource XML but leave a sha256 reference.
    dataElement.innerText = file.sha256!;

    return file;
  }

  // Example:
  //  <![CDATA[
  //    <?xml version='1.0' encoding='UTF-8' standalone='no'?>
  //    <!DOCTYPE en-note SYSTEM 'http://xml.evernote.com/pub/enml2.dtd'>
  //    <en-note>
  //      <div>Text</div>
  //      <div><br /></div>
  //      <en-media style='--en-naturalWidth:742; --en-naturalHeight:499;' hash='a65a0b23dae06d6a4409d5b86973ba98' type='image/png' />
  //      <div><br /></div>
  //    </en-note>
  //  ]]>
  Future<List<Block>> _processNoteContent(
    String? noteTitle,
    XmlElement noteContentElement,
    List<File?> files,
    Map<String, String> md5toSha256Mappings,
    Map<String, String> sha256ToFileIdMappings,
  ) async {
    // Index 0 is a CDATA node
    final data = noteContentElement.children[1].value;

    if (data == null) {
      logger.w('No note data');
      return [];
    }

    final contentDocument = XmlDocument.parse(data);
    var contentElement = contentDocument.getElement('en-note');

    if (contentElement == null) {
      logger.w('No content!');
      return [];
    }

    final List<String> sha256Hashes = [];

    // Replace existing en-media hashes in the note content with sha256s
    // This is so we can preserve the XML should we ever need to re-hydrate back to EN format
    final mediaElements = contentElement.findAllElements('en-media');
    for (final element in mediaElements) {
      final hash = element.getAttribute('hash');

      // Sometimes the hash can be 'undefined'
      // <en-media hash='undefined' type='image/png' ></en-media>
      if (hash != 'undefined') {
        final sha256Hash = md5toSha256Mappings[hash];

        if (sha256Hash == null) {
          logger.w('Could not find matching hash for note $noteTitle');
        } else {
          sha256Hashes.add(sha256Hash);
          element.setAttribute('hash', sha256Hash);
        }
      }
    }

    final List<Block> blocks = [];
    await extractAndSaveHtml(contentElement, noteTitle, blocks);

    // Resolve SHA256 hashes to file ids and create the additional blocks
    for (final hash in sha256Hashes) {
      final fileBlock = Block(type: BlockType.file);
      fileBlock.data = sha256ToFileIdMappings[hash];
      blocks.add(fileBlock);
    }

    return blocks;
  }

  Future<void> extractAndSaveHtml(
    XmlElement contentElement,
    String? noteTitle,
    List<Block> blocks,
  ) async {
    String contentData;

    // Copy the XML
    final clonedElement = contentElement.copy();

    if (clonedElement.firstElementChild == null) {
      contentData = clonedElement.innerXml;
    } else {
      // Strip off the <en-note> tag
      final formattedContent = clonedElement.firstElementChild!;

      final mediaElements = formattedContent.findAllElements('en-media');

      // Remove any inline media elements (we will render them after the HTML)
      for (final mediaElement in mediaElements) {
        mediaElement.remove();
      }

      // If there is no actual text in the content then this note only has attachments.
      if (formattedContent.innerText.isEmpty) {
        return;
      }

      contentData = formattedContent.innerXml;
    }

    final contentFile = await logic.createOrGetExistingFileFromBytes(
        stringToUint8List(contentData), '$noteTitle.html');

    await logic.saveFile(contentFile);

    final contentFileBlock = Block(type: BlockType.file);
    contentFileBlock.data = contentFile.id;

    blocks.add(contentFileBlock);
  }

  String? _getFileNameFromResourceAttributesElement(
      XmlElement resourceAttributesElement) {
    final fileName = resourceAttributesElement.getElement('file-name');

    if (fileName != null) {
      return fileName.innerText;
    }

    logger.i('No filename');
    return null;
  }
}
