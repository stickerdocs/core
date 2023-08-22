import 'package:stickerdocs_core/src/hlc.dart';
import 'package:stickerdocs_core/src/main.dart';

class ClockService {
  Hlc? _canonicalTime;
  String? formattedClientId;

  Future<Hlc> _getCanonicalTime() async {
    if (_canonicalTime != null) {
      return _canonicalTime!;
    }

    // We only need the first 8 chars of the client ID
    formattedClientId = (await config.clientId).substring(0, 8);

    _canonicalTime = Hlc.zero(formattedClientId);
    return _canonicalTime!;
  }

  Future<String> getTime() async {
    // Compute new HLC timestamp
    _canonicalTime = Hlc.send(await _getCanonicalTime());
    return _canonicalTime.toString();
  }

  bool isBNewer(String a, String b) {
    return Hlc.parse(b) > Hlc.parse(a);
  }
}
