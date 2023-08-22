import 'package:stickerdocs_core/src/utils.dart';

final namePattern = RegExp(r"^[\w \'.]{3,75}$");

final emailPattern =
    RegExp(r'^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-_]+\.[a-zA-Z0-9-._]+$');
final challengeResponsePattern = RegExp(r'^[0-9]{6}');

final uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

// Only allow certain column names, we need numbers for 'md5', 'ha256' to work.
// Could have just restricted to 256 but this is simpler
final eventKeyPattern = RegExp(r'^[a-z_0-9]{1,75}$');

bool isUuidValid(String input) {
  return uuidPattern.hasMatch(input);
}

String? validateUuid(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Token required';
  }

  if (!isUuidValid(input.trim())) {
    return 'Invalid token';
  }

  return null;
}

bool isEventKeyValid(String input) {
  return eventKeyPattern.hasMatch(input);
}

String? validateName(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Name required';
  }

  if (input.trim().length < 3) {
    return 'Name too short (min 3 characters)';
  }

  if (input.trim().length > 75) {
    return 'Name too long (max 75 characters)';
  }

  if (!namePattern.hasMatch(input.trim())) {
    return 'Invalid name';
  }

  return null;
}

String? validateEmail(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Email required';
  }

  if (input.trim().length < 5) {
    return 'Email too short (min 5 characters)';
  }

  if (input.trim().length > 200) {
    return 'Email too long (max 200 characters)';
  }

  if (!emailPattern.hasMatch(input.trim())) {
    return 'Invalid email';
  }

  return null;
}

String? validatePassword(String? input) {
  if (input == null || input.isEmpty) {
    return 'Password required';
  }

  if (input.trim().length < 10) {
    return 'Password too short (min 10 characters)';
  }

  return null;
}

String? validateChallengeResponse(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Code required';
  }

  if (!challengeResponsePattern.hasMatch(input.trim())) {
    return 'Invalid code';
  }

  return null;
}

String? validateSupportMessage(String? input) {
  if (input == null || input.isEmpty) {
    return 'Message required';
  }

  if (input.length > 5000) {
    return 'Message too long (max 5000 characters)';
  }

  return null;
}

String? validateInvitationToken(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Token required';
  }

  if (formatInvitationToken(input).length != 8) {
    return 'Invalid token';
  }

  return null;
}
