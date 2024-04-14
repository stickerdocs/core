final _sdidPattern = RegExp(
    r'^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{22}$');

// Only allow certain column names, we need numbers for 'md5', 'ha256' to work.
// Could have just restricted to 256 but this is simpler
final _eventKeyPattern = RegExp(r'^[a-z_0-9]{1,75}$');

bool isSDIDValid(String input) {
  return _sdidPattern.hasMatch(input);
}

bool isEventKeyValid(String input) {
  return _eventKeyPattern.hasMatch(input);
}
