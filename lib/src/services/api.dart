import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import 'package:stickerdocs_core/src/app_logic.dart';
import 'package:stickerdocs_core/src/main.dart';
import 'package:stickerdocs_core/src/models/api/account_details_response.dart';
import 'package:stickerdocs_core/src/models/api/auth_request.dart';
import 'package:stickerdocs_core/src/models/api/challenge_response.dart';
import 'package:stickerdocs_core/src/models/api/change_email_request.dart';
import 'package:stickerdocs_core/src/models/api/change_password_request.dart';
import 'package:stickerdocs_core/src/models/api/delete_account_verify_request.dart';
import 'package:stickerdocs_core/src/models/api/encrypted_invitation.dart';
import 'package:stickerdocs_core/src/models/api/file_get_response.dart';
import 'package:stickerdocs_core/src/models/api/file_put_request.dart';
import 'package:stickerdocs_core/src/models/api/invitation_request.dart';
import 'package:stickerdocs_core/src/models/api/invitation_response.dart';
import 'package:stickerdocs_core/src/models/api/login_request.dart';
import 'package:stickerdocs_core/src/models/api/login_response.dart';
import 'package:stickerdocs_core/src/models/api/register_request.dart';
import 'package:stickerdocs_core/src/models/api/register_response.dart';
import 'package:stickerdocs_core/src/models/api/report_harmful_content.dart';
import 'package:stickerdocs_core/src/models/event_file.dart';
import 'package:stickerdocs_core/src/models/file_chunk.dart';
import 'package:stickerdocs_core/src/models/invitation_info.dart';
import 'package:stickerdocs_core/src/utils.dart';

class APIService {
  final String baseUrl;
  final String appName;
  final String appVersion;
  bool isCurrentVersionSupported = true;
  final http.Client _client = http.Client();

  static const _userAgentHeader = 'User-Agent';
  static const _clientIdHeader = 'Client-Id';
  static const _userIdHeader = 'User-Id';
  static const _sourceUserIdHeader = 'Source-User-Id';
  static const _requestIdHeader = 'Request-Id';
  static const _signatureHeader = 'Signature';
  // Note this X-Sanity response header is lower-case
  static const _sanityResponseHeader = 'x-sanity';

  APIService(this.baseUrl, this.appName, this.appVersion);

  Future<http.Response> sendGet(String path,
      {Map<String, String>? additionalHeaders}) async {
    if (!isCurrentVersionSupported) {
      return http.Response('', HttpStatus.upgradeRequired);
    }

    String url = '$baseUrl$path';
    Map<String, String> headers =
        await buildHeaders('GET/$path', additionalHeaders, null);

    final response = await _client.get(Uri.parse(url), headers: headers);
    return await processResponse('GET', url, headers, null, response);
  }

  Future<http.Response> sendPost(String path,
      {Object? body, Map<String, String>? additionalHeaders}) async {
    if (!isCurrentVersionSupported) {
      return http.Response('', HttpStatus.upgradeRequired);
    }

    String url = '$baseUrl$path';
    String? formattedBody = body == null ? null : json.encode(body);

    Map<String, String> headers =
        await buildHeaders('POST/$path', additionalHeaders, formattedBody);

    final response = await _client.post(Uri.parse(url),
        body: formattedBody, headers: headers);
    return await processResponse('POST', url, headers, formattedBody, response);
  }

  Future<http.Response> sendPut(String path,
      {Object? body, Map<String, String>? additionalHeaders}) async {
    if (!isCurrentVersionSupported) {
      return http.Response('', HttpStatus.upgradeRequired);
    }

    String url = '$baseUrl$path';
    String? formattedBody = body == null ? null : json.encode(body);

    Map<String, String> headers =
        await buildHeaders('PUT/$path', null, formattedBody);

    final response = await _client.put(Uri.parse(url),
        body: formattedBody, headers: headers);
    return await processResponse('PUT', url, headers, formattedBody, response);
  }

  Future<http.Response> sendDelete(String path) async {
    if (!isCurrentVersionSupported) {
      return http.Response('', HttpStatus.upgradeRequired);
    }

    String url = '$baseUrl$path';
    Map<String, String> headers =
        await buildHeaders('DELETE/$path', null, null);

    final response = await _client.delete(Uri.parse(url), headers: headers);
    return await processResponse('DELETE', url, headers, null, response);
  }

  Future<Map<String, String>> buildHeaders(
      String path, Map<String, String>? additionalHeaders, String? body) async {
    SplayTreeMap<String, String> headers = SplayTreeMap<String, String>();

    headers.addAll({
      _userAgentHeader: 'StickerDocs App/$appVersion',
      _clientIdHeader: await config.clientId,
    });

    final userId = await config.userId;

    if (userId != null) {
      headers[_userIdHeader] = userId;
      headers[_requestIdHeader] = newUuid();
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    final serializedHeaders = jsonEncode(headers);
    final signature =
        await crypto.signApiRequest(path, serializedHeaders, body);

    if (signature != null) {
      headers[_signatureHeader] = signature;
    }

    return headers;
  }

  Future<http.Response> processResponse(
      String method,
      String url,
      Map<String, String> headers,
      String? formattedBody,
      http.Response response) async {
    final log = response.statusCode == HttpStatus.ok ? logger.d : logger.e;
    log('${response.statusCode}: $method $url');

    logger.t(headers);

    if (formattedBody != null && formattedBody.isNotEmpty) {
      logger.t('>> $formattedBody');
    }

    if (response.body.isNotEmpty) {
      logger.t('<< ${json.encode(response.body)}');
    }

    final latestVersion = response.headers['x-latest-version-number'];
    if (latestVersion != null) {
      final releaseNotes = response.headers['x-latest-version-release-notes'];
      isCurrentVersionSupported =
          response.statusCode != HttpStatus.upgradeRequired;

      GetIt.I<AppLogic>().upgradeAvailable(
          latestVersion, releaseNotes, isCurrentVersionSupported);

      if (!isCurrentVersionSupported) {
        return response;
      }
    }

    final serviceMessage = response.headers['x-service-message'];
    if (serviceMessage != null) {
      GetIt.I<AppLogic>().serviceMessage(serviceMessage);
    }

    return response;
  }

  Future<bool?> isRegistrationOpen() async {
    http.Response response;

    try {
      response = await sendGet('account/register');
    } catch (e) {
      return null;
    }

    if (response.statusCode != HttpStatus.ok) {
      return null;
    }

    return response.statusCode == HttpStatus.ok && response.body == 'open';
  }

  Future<bool> joinWaitingList(String email) async {
    final response = await sendPost('account/register/waiting_list', body: {
      'email': email,
    });

    return response.statusCode == HttpStatus.ok;
  }

  Future<RegisterResponse?> register(RegisterRequest request) async {
    final response = await sendPut('account/register', body: request);

    if (response.statusCode == HttpStatus.ok) {
      return RegisterResponse.deserialize(response.body);
    }

    return null;
  }

  Future<Uint8List?> registerVerify(
      Uint8List challengeResponse, String userId) async {
    final response = await sendPost('account/register', body: {
      'challenge_response': uint8ListToBase64(challengeResponse),
    }, additionalHeaders: {
      _userIdHeader: userId
    });

    if (response.statusCode == HttpStatus.ok) {
      return base64ToUint8List(response.body);
    }

    return null;
  }

  Future<AccountDetailsResponse?> getAccountDetails() async {
    try {
      final response = await sendGet('account');

      if (response.statusCode == HttpStatus.ok) {
        return AccountDetailsResponse.deserialize(response.body);
      }
    } catch (exception) {
      // Ignore
    }

    return null;
  }

  Future<bool> logout() async {
    final response = await sendPost('account/logout');
    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> logoutOtherSessions() async {
    final response = await sendPost('account/logout/other-sessions');
    return response.statusCode == HttpStatus.ok;
  }

  Future<LoginResponse?> login(LoginRequest request) async {
    final response = await sendPut('account/login', body: request);

    if (response.statusCode == HttpStatus.ok) {
      return LoginResponse.deserialize(response.body);
    }

    return null;
  }

  Future<Uint8List?> loginVerify(
      Uint8List challengeResponse, String userId) async {
    final response = await sendPost('account/login', body: {
      'challenge_response': uint8ListToBase64(challengeResponse),
    }, additionalHeaders: {
      _userIdHeader: userId
    });

    if (response.statusCode == HttpStatus.ok) {
      return base64ToUint8List(response.body);
    }

    return null;
  }

  Future<bool> subscribe(String token) async {
    try {
      final response = await sendPost('account/subscribe', body: {
        'token': token,
      });

      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      return false;
    }
  }

  Future<bool> subscribeViaApple(String transactionId) async {
    try {
      final response = await sendPost('account/subscribe/apple', body: {
        'transaction_id': transactionId,
      });

      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendSupportEnquiry(String? email, String message) async {
    final body = {'message': message};

    if (email != null && email.isNotEmpty) {
      body['email'] = email;
    }

    final response = await sendPost('support/contact', body: body);

    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> submitCrashReport(String report) async {
    final body = {'report': report};

    final response = await sendPost('support/report-crash', body: body);
    return response.statusCode == HttpStatus.ok;
  }

  Future<List<String>> putFile(FilePutRequest request) async {
    final response = await sendPut('file/${request.fileId}', body: request);

    if (response.statusCode == HttpStatus.ok) {
      List<dynamic> decoded = jsonDecode(response.body);
      return decoded.map((url) => url.toString()).toList();
    }

    return [];
  }

  Future<String?> putFileChunk(FileChunk fileChunk, Uint8List? data) async {
    Map<String, dynamic>? formattedBody =
        data == null ? null : {'data': uint8ListToBase64(data)};

    final response = await sendPut(
        'file/${fileChunk.fileId}/chunk/${fileChunk.index}',
        body: formattedBody);

    if (response.statusCode == HttpStatus.ok) {
      return response.body;
    }

    return null;
  }

  Future<AccountDetailsResponse?> fileUploadSuccessful(String fileId) async {
    final response = await sendPost('file/$fileId');

    if (response.statusCode == HttpStatus.ok) {
      return AccountDetailsResponse.deserialize(response.body);
    }

    return null;
  }

  Future<FileGetResponse?> getFile(String fileId, String? sourceUserId) async {
    final headers = <String, String>{};

    if (sourceUserId != null) {
      headers[_sourceUserIdHeader] = sourceUserId;
    }

    final response = await sendGet('file/$fileId', additionalHeaders: headers);

    // Check this x-sanity (lower-case) response header to be sure if a 404 occurs it really is because the file was not found
    // rather than some other server/appliance/misconfiguration which could cause clients to incorrectly
    // consider files have been removed when they have not.
    if (response.statusCode == HttpStatus.notFound &&
        response.headers[_sanityResponseHeader] == 'StickerDocs') {
      return FileNotFoundFileGetResponse.create();
    }

    if (response.statusCode == HttpStatus.ok) {
      return FileGetResponse.deserialize(response.body, fileId, sourceUserId);
    }

    return null;
  }

  Future<String?> getFileChunk(FileChunk fileChunk) async {
    final headers = <String, String>{};

    if (fileChunk.sourceUserId != null) {
      headers[_sourceUserIdHeader] = fileChunk.sourceUserId!;
    }

    final response = await sendGet(
        'file/${fileChunk.fileId}/chunk/${fileChunk.index}',
        additionalHeaders: headers);

    // Check this x-sanity (lower-case) response header to be sure if a 404 occurs it really is because the file was not found
    // rather than some other server/appliance/misconfiguration which could cause clients to incorrectly
    // consider files have been removed when they have not.
    if (response.statusCode == HttpStatus.notFound &&
        response.headers[_sanityResponseHeader] == 'StickerDocs') {
      return FileChunk.notFoundSignature;
    }

    if (response.statusCode == HttpStatus.ok) {
      return response.body;
    }

    return null;
  }

  Future<bool> deleteFile(String fileId) async {
    final response = await sendDelete('file/$fileId');
    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> sendInvitation(InvitationRequest request) async {
    final response = await sendPost('invite', body: request);
    return response.statusCode == HttpStatus.ok;
  }

  Future<InvitationResponse?> getInvitationStatus(String invitationId) async {
    final response = await sendGet('invite/$invitationId');

    if (response.statusCode == HttpStatus.ok) {
      return InvitationResponse.deserialize(response.body);
    }

    return null;
  }

  Future<bool> cancelInvitation(String invitationId) async {
    final response = await sendPost('invite/$invitationId/cancel');
    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> approveInvitation(String invitationId) async {
    final response = await sendPost('invite/$invitationId/approve');
    return response.statusCode == HttpStatus.ok;
  }

  Future<EncryptedInvitation?> getEncryptedInvitation(String token) async {
    final response = await sendGet('invitation/$token');

    if (response.statusCode == HttpStatus.ok) {
      return EncryptedInvitation.deserialize(response.body);
    }

    return null;
  }

  Future<InvitationInfo?> getInvitationDetails(
      String token, Uint8List signature) async {
    final response = await sendPost('invitation/$token',
        body: {'signature': uint8ListToBase64(signature)});

    if (response.statusCode == HttpStatus.ok) {
      return InvitationInfo.deserialize(response.body);
    }

    return null;
  }

  Future<bool> acceptInvitation(String token, Uint8List signature) async {
    final response = await sendPost('invitation/$token/accept',
        body: {'signature': uint8ListToBase64(signature)});

    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> rejectInvitation(String token, Uint8List signature) async {
    final response = await sendPost('invitation/$token/reject',
        body: {'signature': uint8ListToBase64(signature)});

    return response.statusCode == HttpStatus.ok;
  }

  Future<List<EventFile>?> sync([EventFile? eventFile]) async {
    final response = await sendPut('sync/self', body: eventFile);

    if (response.statusCode == HttpStatus.ok) {
      return EventFile.deserialize(response.body);
    }

    return null;
  }

  Future<List<EventFile>?> syncShared(String userId,
      [EventFile? eventFile]) async {
    final response = await sendPut('sync/share/$userId', body: eventFile);

    if (response.statusCode == HttpStatus.ok) {
      return EventFile.deserialize(response.body);
    }

    return null;
  }

  Future<bool> syncSuccess(EventFile eventFile) async {
    final owner = eventFile.sourceUserId == null
        ? 'self'
        : 'share/${eventFile.sourceUserId}';

    final response = await sendPost('sync/$owner',
        body: {'first_timestamp': eventFile.firstTimestamp});

    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> reportHarmfulContent(ReportHarmfulContent harmfulContent) async {
    final response =
        await sendPost('support/report-harmful-content', body: harmfulContent);
    return response.statusCode == HttpStatus.ok;
  }

  Future<ChallengeResponse?> changePassword(AuthRequest request) async {
    final response = await sendPut('account/update/password', body: request);

    if (response.statusCode == HttpStatus.ok) {
      return ChallengeResponse.deserialize(response.body);
    }

    return null;
  }

  Future<bool> changePasswordVerify(ChangePasswordVerifyRequest request) async {
    final response = await sendPost('account/update/password', body: request);
    return response.statusCode == HttpStatus.ok;
  }

  Future<ChallengeResponse?> changeEmail(AuthRequest request) async {
    final response = await sendPut('account/update/email', body: request);

    if (response.statusCode == HttpStatus.ok) {
      return ChallengeResponse.deserialize(response.body);
    }

    return null;
  }

  Future<bool> changeEmailVerify(ChangeEmailVerifyRequest request) async {
    final response = await sendPost('account/update/email', body: request);
    return response.statusCode == HttpStatus.ok;
  }

  Future<bool> changeAccountName(String name) async {
    final response = await sendPost('account/update/name', body: {
      'name': name,
    });

    return response.statusCode == HttpStatus.ok;
  }

  Future<ChallengeResponse?> deleteAccount(AuthRequest request) async {
    final response = await sendPost('account/delete', body: request);

    if (response.statusCode == HttpStatus.ok) {
      return ChallengeResponse.deserialize(response.body);
    }

    return null;
  }

  Future<bool> deleteAccountVerify(DeleteAccountVerifyRequest request) async {
    final response = await sendPost('account/delete/verify', body: request);
    return response.statusCode == HttpStatus.ok;
  }
}
