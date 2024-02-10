import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:mime/mime.dart';
import 'package:mutex/mutex.dart';
import 'package:path/path.dart';

import 'package:stickerdocs_core/models.dart';
import 'package:stickerdocs_core/src/app_state.dart';
import 'package:stickerdocs_core/src/importers/evernote.dart';
import 'package:stickerdocs_core/src/models/api/account_details_response.dart';
import 'package:stickerdocs_core/src/models/api/report_harmful_content.dart';
import 'package:stickerdocs_core/src/models/db/block.dart';
import 'package:stickerdocs_core/src/models/invitation.dart';
import 'package:stickerdocs_core/src/services/api.dart';
import 'package:stickerdocs_core/src/services/config.dart';
import 'package:stickerdocs_core/src/services/crypto.dart';
import 'package:stickerdocs_core/src/services/db.dart';
import 'package:stickerdocs_core/src/services/file.dart';
import 'package:stickerdocs_core/src/services/sync.dart';
import 'package:stickerdocs_core/src/temp_file.dart';
import 'package:stickerdocs_core/src/utils.dart';
import 'package:stickerdocs_core/src/main.dart';

enum AppLogicResult {
  offline,
  notLoggedIn,
  apiError,
  dbError,
  cryptoError,
  missedStepError,
  accountActionDoesNotRequireChallenge,
  ok
}

enum FileSource {
  filePicker,
  imagePicker,
  documentScanner,
  photo,
}

enum SearchContext {
  documents,
  stickers,
}

class AppLogic {
  final DBService _db = GetIt.I.get<DBService>();
  final APIService _api = GetIt.I.get<APIService>();
  final FileService _fileService = GetIt.I.get<FileService>();
  final SyncService _syncService = GetIt.I.get<SyncService>();
  final AppState appState;
  final Mutex fileAddMutex = Mutex();
  final Mutex syncMutex = Mutex();
  final List<String> _processedFilePaths = [];

  /// This is only used during registration and login as a bridge between the initial request and the verification
  String? _ephemeralEmail;

  /// This is only used during login as a bridge between the initial request and the verification
  String? _ephemeralUserId;

  /// Only initialized if used
  EvernoteImporter? _evernoteImporterInstance;

  Invitation? _invitation;
  Uint8List? _invitationSignature;

  AppLogic(this.appState);

  EvernoteImporter get _evernoteImporter {
    _evernoteImporterInstance ??= EvernoteImporter(this);
    return _evernoteImporterInstance!;
  }

  Future<void> init() async {
    await _firstRun();
    await clearTemporaryFiles();
    await searchDocuments();
    await searchStickers();
    await populateInvitedUsers();
    await populateTrustedUsers();

    final userEmail = await config.userEmail;

    if (userEmail != null) {
      appState.accountDetails.value = AccountDetails(email: userEmail);
      sync(); // Don't await
    }
  }

  Future<void> _firstRun() async {
    if (!await config.isFirstRun) {
      return;
    }

    await config.persistClientId();
    await config.setFirstRunCompleted();
  }

  Future<void> setAppDBValue(String key, String value) async {
    await _db.setAppConfig(key, value);
  }

  Future<String?> getAppDBValue(String key) async {
    return _db.getAppConfig(key);
  }

  Future<bool> sendSupportEnquiry(String? email, String message) async {
    return await api.sendSupportEnquiry(email, message);
  }

  Future<void> searchDocuments() async {
    appState.documents.value =
        await _db.searchDocuments(appState.documentSearchController.text);
  }

  Future<void> searchStickers() async {
    appState.stickers.value =
        await _db.searchStickers(appState.stickerSearchController.text);
  }

  Future<void> populateInvitedUsers() async {
    appState.invitedUsers.value = await _db.getInvitations();
  }

  Future<void> populateTrustedUsers() async {
    appState.trustedUsers.value = await _db.getTrustedUsers();
  }

  Future<bool?> isRegistrationOpen() async {
    return await _api.isRegistrationOpen();
  }

  Future<bool> joinRegistrationWaitingList(String email) async {
    return await _api.joinWaitingList(email);
  }

  Future<AppLogicResult> register(
    String name,
    String email,
    String password,
    String? token,
  ) async {
    _ephemeralEmail = email;

    if (token != null) {
      token = token.trim();
    }

    final request = await crypto.generateRegistrationData(
        name.trim(), email.trim(), password.trim(), token);

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final response = await _api.register(request);

    if (response == null) {
      return AppLogicResult.apiError;
    }

    _ephemeralUserId = response.userId;

    if (response.challengeResponse != null) {
      final result = await registerVerify(response.challengeResponse!);

      if (result == AppLogicResult.ok) {
        return AppLogicResult.accountActionDoesNotRequireChallenge;
      }

      return result;
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> registerVerify(String challengeResponse) async {
    if (_ephemeralUserId == null) {
      return AppLogicResult.missedStepError;
    }

    final request =
        crypto.generateAuthChallengeResponse(challengeResponse.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final encryptedResponse =
        await _api.registerVerify(request, _ephemeralUserId!);

    if (encryptedResponse == null) {
      return AppLogicResult.apiError;
    }

    await setProfile(config, _db, _ephemeralEmail!, true);

    await crypto.decryptRegisterVerifyResponseAndPersist(encryptedResponse);

    await config.setUserId(_ephemeralUserId);
    await config.setUserEmail(_ephemeralEmail);

    // Clear temporary variables
    _ephemeralUserId = null;
    _ephemeralEmail = null;

    await updateAccountDetails();

    sync(retrieveAccountDetails: false); // Don't await

    return AppLogicResult.ok;
  }

  serviceMessage(String message) {
    // Only if there has not already been a service message in this app-session.
    // Don't want to bombard the user
    if (appState.serviceMessage.value != message) {
      appState.serviceMessage.value = message;
    }
  }

  upgradeAvailable(String latestVersion, String? releaseNotes,
      bool isCurrentVersionSupported) {
    appState.upgradeAvailable.value = UpgradeAvailable(
        version: latestVersion,
        releaseNotes: releaseNotes,
        isCurrentVersionSupported: isCurrentVersionSupported);
  }

  Future<AppLogicResult> logout({bool shouldNotifyServer = true}) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    //   // TODO: queue up a logout request for when online and do the logout then
    // }

    // this is normally the case, unless the API returned unauthorised
    if (shouldNotifyServer) {
      final result = await sync();

      if (result != AppLogicResult.ok) {
        return result;
      }

      final logoutSuccessful = await _api.logout();

      if (!logoutSuccessful) {
        logger.e('Could not log out');
        return AppLogicResult.apiError;
      }
    }

    await config.logout();

    appState.accountDetails.value = null;
    appState.documents.value.clear();
    appState.documentSearchController.clear();
    appState.stickers.value.clear();
    appState.stickerSearchController.clear();
    appState.invitationToAccept.value = null;
    appState.invitedUsers.value = [];
    _processedFilePaths.clear();

    await setProfile(config, _db, null, false);
    await init();

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> logoutOtherSessions() async {
    final logoutSuccessful = await _api.logoutOtherSessions();

    if (!logoutSuccessful) {
      logger.e('Could not expire other sessions');
      return AppLogicResult.apiError;
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> login(String email, String password) async {
    _ephemeralEmail = email;

    final request = crypto.generateLoginData(email.trim(), password.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final response = await _api.login(request);

    if (response == null) {
      return AppLogicResult.apiError;
    }

    _ephemeralUserId = response.userId;

    if (response.challengeResponse != null) {
      final result = await loginVerify(response.challengeResponse!);

      if (result == AppLogicResult.ok) {
        return AppLogicResult.accountActionDoesNotRequireChallenge;
      }

      return result;
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> loginVerify(String challengeResponse) async {
    if (_ephemeralUserId == null) {
      return AppLogicResult.missedStepError;
    }

    final request =
        crypto.generateAuthChallengeResponse(challengeResponse.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final encryptedResponse =
        await _api.loginVerify(request, _ephemeralUserId!);

    if (encryptedResponse == null) {
      return AppLogicResult.apiError;
    }

    await setProfile(config, _db, _ephemeralEmail!, false);

    await crypto.decryptLoginVerifyResponseAndPersist(encryptedResponse);

    // We need to save the client ID as this could be an empty DB
    await config.persistClientId();
    await config.setUserId(_ephemeralUserId);

    // Clear temporary variables
    _ephemeralUserId = null;
    _ephemeralEmail = null;

    await updateAccountDetails();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<AppLogicResult> changePassword(
      String currentPassword, String newPassword) async {
    final email = await config.userEmail;

    if (email == null) {
      return AppLogicResult.missedStepError;
    }

    final request =
        crypto.generateChangePasswordRequest(email, currentPassword.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final response = await _api.changePassword(request);

    if (response == null) {
      return AppLogicResult.apiError;
    }

    if (response.challengeResponse != null) {
      final result =
          await changePasswordVerify(response.challengeResponse!, newPassword);

      if (result == AppLogicResult.ok) {
        return AppLogicResult.accountActionDoesNotRequireChallenge;
      }

      return result;
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> changePasswordVerify(
      String challengeResponse, String newPassword) async {
    final email = await config.userEmail;

    if (email == null) {
      return AppLogicResult.missedStepError;
    }

    final challengeResponseData =
        crypto.generateAuthChallengeResponse(challengeResponse.trim());

    if (challengeResponseData == null) {
      return AppLogicResult.cryptoError;
    }

    // TODO: do we need to re-encrypt the data keys?

    final request =
        crypto.generateChangePasswordRequest(email, newPassword.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    request.challengeResponse = challengeResponseData;

    final success = await _api.changePasswordVerify(request);

    if (!success) {
      return AppLogicResult.apiError;
    }

    return AppLogicResult.ok;
  }

  Future<bool> subscribe(String token) async {
    if (!(await api.subscribe(token))) {
      return false;
    }

    await updateAccountDetails();

    sync(); // Don't await
    return true;
  }

  Future<bool> exportData(String pathToExportTo) async {
    final dbFile = io.File(config.dbPath);

    // Format the db filename e.g. db_2023-11-14T22-16-40
    var dbFileName = 'db_${isoDateToStringNow()}';
    dbFileName = dbFileName.replaceAll(':', '-').split('.')[0];

    await dbFile.copy(join(pathToExportTo, dbFileName));

    final fileIds = await _db.getAllFileIds();

    for (final fileId in fileIds) {
      // Create the destination directory if required
      await io.Directory(join(pathToExportTo, fileId)).create();

      final File file = (await _db.getFileById(fileId))!;

      final destinationFilePath =
          join(pathToExportTo, fileId, file.formatName());

      if (await _shouldFileBeExported(destinationFilePath, file.size!)) {
        await file.getFile().copy(destinationFilePath);
      }
    }

    return true;
  }

  Future<bool> _shouldFileBeExported(
      String destinationFilePath, int fileSize) async {
    final destinationFile = io.File(destinationFilePath);

    if (await destinationFile.exists()) {
      return await destinationFile.length() != fileSize;
    }

    return true;
  }

  // These paths could be files or directories
  Future<void> addFiles(List<String> filePaths, FileSource source) async {
    // Use a mutex to try to address the issue of duplicate file drop events
    return await fileAddMutex.protect(() async {
      filePaths.removeWhere((element) => _processedFilePaths.contains(element));
      await _addFiles(filePaths, source);
      _processedFilePaths.addAll(filePaths);
    });
  }

  Future<void> _addFiles(List<String> paths, FileSource source) async {
    final filePaths = <String>[];

    for (final path in paths) {
      final directory = io.Directory(path);

      if (await directory.exists()) {
        await for (final entity
            in directory.list(recursive: true, followLinks: false)) {
          if (entity is io.File) {
            filePaths.add(entity.path);
          }
        }
      } else {
        filePaths.add(path);
      }
    }

    await Future.wait([
      for (final filePath in filePaths) _addFileDocumentByPath(filePath, source)
    ]);

    sync(); // Don't await
  }

  Future<void> _addFileDocumentByPath(
      String filePath, FileSource source) async {
    final file = io.File(filePath);
    if (await file.exists()) {
      final stat = await file.stat();

      // Max file size is 10GB, which is 10 * 1024^3 bytes, which is 10,737,418,240 bytes
      if (stat.size > 10737418240) {
        appState.errorMessages.value.add(
            'File $filePath cannot be added as it is larger than the maximum file size limit of 10GB.');
        return;
      }
    } else {
      appState.errorMessages.value.add('File $filePath cannot be opened.');
      return;
    }

    // This is not ready for prod yet
    // if (basename(filePath).toLowerCase().endsWith('.enex')) {
    //   await _evernoteImporter.import(file);

    //   // Call this to update the document list but don't await
    //   searchDocuments();

    //   return;
    // }

    // Do some filename modifications
    String fileName = basename(file.path);
    String documentTitle = fileName.replaceAll(extension(file.path), '');

    if (source == FileSource.photo && fileName.contains('image_picker')) {
      fileName = 'Photo${extension(file.path)}';
      documentTitle = 'Photo';
    } else if (source == FileSource.imagePicker &&
        fileName.contains('image_picker')) {
      fileName = 'Image${extension(file.path)}';
      documentTitle = 'Image';
    } else if (source == FileSource.documentScanner &&
        fileName.contains('vision_kit')) {
      fileName = 'Scanned Document${extension(file.path)}';
      documentTitle = 'Scanned Document';
    }

    await _addFileDocumentFromFile(file, fileName, documentTitle);
  }

  Future<FileDocument> _addFileDocumentFromFileModelObject(
      File file, String? fileName) async {
    final fileDocumentTitle =
        fileName == null ? null : basenameWithoutExtension(fileName);

    if (file.isNew) {
      await saveFile(file);
    } else {
      final fileDocument = await _db.getFileDocumentByFileId(file.id);
      if (fileDocument != null && fileDocument.title == fileDocumentTitle) {
        return fileDocument;
      }
    }

    final fileDocument = FileDocument(fileId: file.id);
    fileDocument.title = fileDocumentTitle;
    await _saveFileDocument(fileDocument);

    // Call this to update the document list but don't await
    searchDocuments();

    return fileDocument;
  }

  Future<FileDocument> addFileDocumentFromBytes(
      Uint8List data, String? fileName) async {
    final file = await createOrGetExistingFileFromBytes(data, fileName);
    return _addFileDocumentFromFileModelObject(file, fileName);
  }

  Future<FileDocument> _addFileDocumentFromFile(
      io.File ioFile, String? fileName, String? documentTitle) async {
    final file = await createOrGetExistingFile(ioFile, fileName);
    return _addFileDocumentFromFileModelObject(file, documentTitle ?? fileName);
  }

  Future<void> _saveFileDocument(FileDocument fileDocument) async {
    await _db.save(fileDocument);
  }

  Future<void> saveFile(File file) async {
    await _db.save(file);
  }

  Future<void> saveBlock(Block block) async {
    await _db.save(block);
  }

  Future<void> saveBlockDocument(BlockDocument blockDocument) async {
    await _db.save(blockDocument);
  }

  Future<Sticker> getOrCreateSticker(String name, {bool save = true}) async {
    var sticker = await _db.getStickerByName(name);

    if (sticker != null) {
      return sticker;
    }

    sticker = Sticker(name: name);

    if (save) {
      await saveSticker(sticker);

      // Call this to update the sticker list but don't await
      searchStickers();
    }

    return sticker;
  }

  Future<Sticker?> getStickerByName(String name) async {
    return _db.getStickerByName(name);
  }

  Future<AppLogicResult> attachStickerToDocument(
      Document document, Sticker sticker) async {
    if (document is FileDocument) {
      await _db.save(StickerFileDocument(
        stickerId: sticker.id,
        fileDocumentId: document.id,
      ));
    } else if (document is BlockDocument) {
      await _db.save(StickerBlockDocument(
        stickerId: sticker.id,
        blockDocumentId: document.id,
      ));
    }

    sync();
    return AppLogicResult.ok;
  }

  Future<void> removeStickerFromDocument(
      Document document, Sticker sticker) async {
    if (document is FileDocument) {
      final object = await _db.getStickerFileDocument(sticker, document);
      if (object != null) {
        await _db.delete(object);
      }
      return;
    }

    if (document is BlockDocument) {
      final object = await _db.getStickerBlockDocument(sticker, document);
      if (object != null) {
        await _db.delete(object);
      }
    }

    return;
  }

  Future<void> saveSticker(Sticker sticker) async {
    await _db.save(sticker);
  }

  Future<AppLogicResult> sendInvitation(
      String recipientName,
      String recipientEmail,
      String passphrase,
      Sticker sticker,
      Uint8List stickerImage) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    // }

    // if (!loggedIn.value) {
    //   return AppLogicResult.notLoggedIn;
    // }

    final invitation = InvitedUser(
      stickerId: sticker.id,
      name: recipientName,
      email: recipientEmail,
    );

    final challenge = await crypto.createInvitation(invitation.id);
    invitation.signingPublicKey = challenge.signingPublicKey;
    invitation.signingPrivateKey = challenge.signingPrivateKey;

    final invitationRequest = crypto.createInvitationRequest(
      challenge,
      sticker,
      stickerImage,
      recipientName,
      recipientEmail,
      passphrase,
    );

    if (invitationRequest == null) {
      return AppLogicResult.cryptoError;
    }

    if (!await _api.sendInvitation(invitationRequest)) {
      // It is possible that we are out of invitations
      await updateAccountDetails();
      return AppLogicResult.apiError;
    }

    await _db.save(invitation);
    await populateInvitedUsers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<AppLogicResult> cancelInvitation(InvitedUser invitedUser) async {
    if (!await _api.cancelInvitation(invitedUser.id)) {
      return AppLogicResult.apiError;
    }

    await _db.delete(invitedUser);
    await populateInvitedUsers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  // 8-character token + corresponding password
  Future<AppLogicResult> getInvitationDetails(
      String token, String passphrase) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    // }

    // if (!loggedIn.value) {
    //   return AppLogicResult.notLoggedIn;
    // }

    token = formatInvitationToken(token);

    final invitationChallenge = await _api.getEncryptedInvitation(token);

    if (invitationChallenge == null) {
      return AppLogicResult.apiError;
    }

    final challengeResponse =
        await crypto.decryptInvitation(invitationChallenge, passphrase);

    if (challengeResponse == null) {
      return AppLogicResult.cryptoError;
    }

    final signature = await crypto.createInvitationSignature(challengeResponse);

    // Get the sticker image and name
    final result = await _api.getInvitationDetails(token, signature);

    if (result == null) {
      return AppLogicResult.apiError;
    }

    _invitation = challengeResponse;
    _invitationSignature = signature;
    appState.invitationInfo.value = result;
    appState.invitedSticker.value = result.toSticker();

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> acceptInvitation(String token) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    // }

    // if (!loggedIn.value) {
    //   return AppLogicResult.notLoggedIn;
    // }

    if (_invitationSignature == null || appState.invitationInfo.value == null) {
      return AppLogicResult.missedStepError;
    }

    final invitationInfo = appState.invitationInfo.value!;

    token = formatInvitationToken(token);

    final trustChallengeResult =
        await _api.acceptInvitation(token, _invitationSignature!);

    if (!trustChallengeResult) {
      return AppLogicResult.apiError;
    }

    _invitationSignature = null;

    final trustedUser = TrustedUser(
        userId: _invitation!.userId,
        name: invitationInfo.senderName,
        email: invitationInfo.senderEmail,
        publicKey: _invitation!.userPublicKey);

    await _db.save(trustedUser);

    final sticker = Sticker(name: invitationInfo.stickerName);
    sticker.id = invitationInfo.stickerId;
    sticker.style = invitationInfo.stickerStyle;
    sticker.setSVG(invitationInfo.stickerSvg);

    await _db.save(sticker);

    final sharedSticker = SharedSticker(
      stickerId: sticker.id,
      trustedUserId: trustedUser.id,
      sharedByMe: false,
      ignoreExternalEvents: false,
    );

    await _db.save(sharedSticker);

    // update the sticker collection right away
    await searchStickers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  void cleanupAcceptInvitation() {
    appState.invitationInfo.value = null;
    appState.invitedSticker.value = null;
  }

  Future<AppLogicResult> rejectInvitation(String token) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    // }

    // if (!loggedIn.value) {
    //   return AppLogicResult.notLoggedIn;
    // }

    if (_invitationSignature == null || appState.invitationInfo.value == null) {
      return AppLogicResult.missedStepError;
    }

    token = formatInvitationToken(token);

    final trustChallengeResult =
        await _api.rejectInvitation(token, _invitationSignature!);

    if (!trustChallengeResult) {
      return AppLogicResult.apiError;
    }

    _invitationSignature = null;
    cleanupAcceptInvitation();

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> getInvitationsToProcess() async {
    final invitations = await _db.getInvitations();

    if (invitations.isEmpty) {
      appState.invitationToAccept.value = null;
      return AppLogicResult.ok;
    }

    final invitationToAccept = appState.invitationToAccept.value;

    // Get the first responded invitation
    for (final invitation in invitations) {
      // Do we already have this invitation outstanding for actioning?
      if (invitationToAccept != null &&
          invitation.id == invitationToAccept.invitedUser.id) {
        return AppLogicResult.ok;
      }

      final result = await getInvitationStatus(invitation);

      // Was the invitation accepted?
      if (result == AppLogicResult.ok) {
        return AppLogicResult.ok;
      }

      // If there was an error (other than invitation not yet excepted), surface that
      if (result != AppLogicResult.missedStepError) {
        return result;
      }
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> getInvitationStatus(InvitedUser invitation) async {
    final invitationStatus = await _api.getInvitationStatus(invitation.id);

    if (invitationStatus == null) {
      return AppLogicResult.missedStepError;
    }

    if (!crypto.verifyTrustChallengeResult(invitation, invitationStatus)) {
      return AppLogicResult.cryptoError;
    }

    final sticker = appState.stickers.value
        .firstWhere((element) => element.id == invitation.stickerId);

    appState.invitationToAccept.value =
        InvitationToAccept(invitation, invitationStatus, sticker);

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> acceptInvitationResponse(
      bool ignoreExternalEvents) async {
    // if (!online.value) {
    //   return AppLogicResult.offline;
    // }

    // if (!loggedIn.value) {
    //   return AppLogicResult.notLoggedIn;
    // }

    // if (invitationToAccept.value == null) {
    //   return AppLogicResult.missedStepError;
    // }

    final invitationToAccept = appState.invitationToAccept.value!;

    if (!(await api.approveInvitation(invitationToAccept.invitedUser.id))) {
      return AppLogicResult.apiError;
    }

    final trustedUser = TrustedUser(
        userId: invitationToAccept.response.userId,
        name: invitationToAccept.response.userName,
        email: invitationToAccept.response.userEmail,
        publicKey: invitationToAccept.response.publicKey);

    await _db.save(trustedUser);
    await _db.delete(invitationToAccept.invitedUser);

    final sharedSticker = SharedSticker(
        stickerId: invitationToAccept.sticker.id,
        trustedUserId: trustedUser.id,
        sharedByMe: true,
        ignoreExternalEvents: ignoreExternalEvents);

    await _db.save(sharedSticker);

    appState.invitationToAccept.value = null;

    await populateInvitedUsers();
    await populateTrustedUsers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<AppLogicResult> rejectInvitationResponse() async {
    if (appState.invitationToAccept.value == null) {
      return AppLogicResult.missedStepError;
    }

    if (!await _api
        .cancelInvitation(appState.invitationToAccept.value!.invitedUser.id)) {
      return AppLogicResult.apiError;
    }

    await _db.delete(appState.invitationToAccept.value!.invitedUser);
    appState.invitationToAccept.value = null;

    await populateInvitedUsers();
    await populateTrustedUsers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<void> updateAccountDetails(
      [AccountDetailsResponse? accountDetailsResponse]) async {
    accountDetailsResponse ??= await api.getAccountDetails();

    if (accountDetailsResponse != null) {
      await config.setUserEmail(accountDetailsResponse.email);
    }

    appState.accountDetails.value = accountDetailsResponse?.toAccountDetails();
  }

  Future<AppLogicResult> sync(
      {bool force = false, bool retrieveAccountDetails = true}) async {
    if (appState.accountDetails.value == null) {
      return AppLogicResult.notLoggedIn;
    }

    return await syncMutex.protect(() async {
      appState.isSynchronising.value = true;

      if (retrieveAccountDetails) {
        // Start by getting the account info
        await updateAccountDetails();
      }

      // TODO: test if quota permits
      // if (subscriptionActive.value) {
      // First upload files, but only if the subscription is active
      await _fileService.uploadFiles();
      // }

      // Then process the events
      final result = await _syncService.sync();

      if (result != true) {
        appState.isSynchronising.value = false;

        //?
        return AppLogicResult.apiError;
      }

      // Update UI as we may be downloading a lot of docs
      searchDocuments();
      searchStickers();

      // TODO:
      // todo downloaded files need to be in the state for a count of downloaded vs remaining to download, upload

      // Download files
      await _fileService.downloadFiles();

      appState.isSynchronising.value = false;

      // updateUi();
      return AppLogicResult.ok;
    });
  }

  Future<File> getFileDocumentFile(FileDocument fileDocument) async {
    return (await _db.getFileById(fileDocument.fileId))!;
  }

  Future<String> prepareFileForExternalAccess(File file) async {
    return await writeFileToTemp(file);
  }

  Future<AppLogicResult> renameSticker(Sticker sticker, String name) async {
    sticker.name = name;
    await _db.save(sticker);

    // Update UI right away
    searchStickers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<AppLogicResult> deleteSticker(Sticker sticker) async {
    await _db.delete(sticker);

    // Update UI right away
    searchStickers();

    sync(); // Don't await
    return AppLogicResult.ok;
  }

  Future<bool> renameSelectedDocument(Document document, String newName) async {
    if (document.title == newName) {
      // Nothing to do
      return true;
    }

    document.title = newName;
    await _db.save(document);

    // Update UI right away
    searchDocuments();

    sync(); // Don't await
    return true;
  }

  Future<bool> hasDocumentBeenShared(Document document) async {
    return await _db.hasDocumentBeenShared(document);
  }

  Future<bool> deleteDocument(Document document) async {
    List<File> filesToDelete = [];

    if (document is FileDocument) {
      final file = await getFileDocumentFile(document);
      filesToDelete.add(file);
    }

    if (document is BlockDocument) {
      final blocks = await logic.getBlocksForBlockDocument(document);
      blocks.forEach((element) {
        // TODO: add block document files to the list
      });
    }

    // TODO: only remove files that are dangling and not used by other documents

    for (final File file in filesToDelete) {
      final success = await _deleteFile(file);
      if (!success) {
        return false;
      }
    }

    // Don't forget to delete the document as well.
    _db.delete(document);

    // Update UI right away
    searchDocuments();

    sync(); // Don't await
    return true;
  }

  Future<bool> _deleteFile(File file) async {
    await file.getFile().delete();

    await _db.deleteFile(file);

    if (appState.accountDetails.value == null) {
      return true;
    }

    final success = await _api.deleteFile(file.id);

    if (!success) {
      return false;
    }

    sync(); // Don't await
    searchDocuments(); // Don't await
    return true;
  }

  Future<AppLogicResult> clearDownloadedData() async {
    for (final file in await _db.getPurgeableFiles()) {
      await purgeFile(file);
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> purgeFile(File file) async {
    await file.getFile().delete();
    await _db.markFileAsNotDownloaded(file);
    return AppLogicResult.ok;
  }

  Future<List<Sticker>> getDocumentStickers(Document document) async {
    return await _db.getDocumentStickers(document);
  }

  Future<void> populateSharedStickers() async {
    appState.sharedStickers.value = await _db.getSharedStickers();
  }

  // Internal methods

  Future<File?> getFileById(String fileId) async {
    final file = await _db.getFileById(fileId);

    // Download the file if required
    if (file != null) {
      if (!await file.getFile().exists()) {
        await _fileService.downloadFile(file);
      }
    }

    return file;
  }

  Future<List<Block>> getBlocksForBlockDocument(
      BlockDocument blockDocument) async {
    return await _db.getBlocksForBlockDocument(blockDocument);
  }

  Future<String?> getMimeType(io.File file, String? fileName) async {
    final fileHandle = await file.open(mode: io.FileMode.read);
    final fileHeader = await fileHandle.read(defaultMagicNumbersMaxLength);
    await fileHandle.close();
    return lookupMimeType(fileName ?? '', headerBytes: fileHeader);
  }

  Future<File> createOrGetExistingFileFromBytes(
      Uint8List data, String? fileName) async {
    // createOrGetExistingFile works on file objects,
    // so put this data in a temporary file and then clean up afterwards
    final ioFile = await writeTemporaryFile(data);

    final file = await createOrGetExistingFile(ioFile, fileName);

    await ioFile.delete();

    return file;
  }

  Future<File> createOrGetExistingFile(io.File file, String? fileName) async {
    final size = (await file.stat()).size;
    final sha256 = await CryptoService.sha256File(file);

    final existingFile = await _db.getFileBySignature(size, sha256);

    if (existingFile != null) {
      return existingFile;
    }

    final newFile = File(
        name: fileName,
        size: size,
        sha256: sha256,
        contentType: await getMimeType(file, fileName),
        uploaded: false,
        downloaded: true);

    // Save file data locally
    await file.copy(newFile.getPath());

    return newFile;
  }

  Future<bool> reportHarmfulContent() async {
    final todo = Uint8List.fromList([1, 2, 3]);
    final harmfulContent = ReportHarmfulContent(
        sharedByUserId: 'TODO',
        fileId: 'TODO',
        encryptedHarmfulContent: todo,
        signedHarmfulContent: todo,
        sha256: 'todo',
        md5: 'todo',
        sharedFileEncryptedPassword: 'todo');

    if (!await _api.reportHarmfulContent(harmfulContent)) {
      return false;
    }
    return true;
  }

  Future<bool> submitCrashReport(String report) async {
    return api.submitCrashReport(report);
  }

  Future<AppLogicResult> deleteAccount(String password) async {
    final email = await config.userEmail;

    if (email == null) {
      return AppLogicResult.missedStepError;
    }

    final request = crypto.generateChallengeRequestData(email, password.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final response = await _api.deleteAccount(request);

    if (response == null) {
      return AppLogicResult.apiError;
    }

    if (response.challengeResponse != null) {
      final result = await deleteAccountVerify(response.challengeResponse!);

      if (result == AppLogicResult.ok) {
        return AppLogicResult.accountActionDoesNotRequireChallenge;
      }

      return result;
    }

    return AppLogicResult.ok;
  }

  Future<AppLogicResult> deleteAccountVerify(String challengeResponse) async {
    final request =
        crypto.generateAuthChallengeResponse(challengeResponse.trim());

    if (request == null) {
      return AppLogicResult.cryptoError;
    }

    final success = await _api.deleteAccountVerify(request);

    if (success) {
      return await logout(shouldNotifyServer: false);
    }

    return AppLogicResult.apiError;
  }
}
