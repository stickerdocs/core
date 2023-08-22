final _uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

// Only allow certain column names, we need numbers for 'md5', 'ha256' to work.
// Could have just restricted to 256 but this is simpler
final _eventKeyPattern = RegExp(r'^[a-z_0-9]{1,75}$');

bool isUuidValid(String input) {
  return _uuidPattern.hasMatch(input);
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
  return _eventKeyPattern.hasMatch(input);
}
