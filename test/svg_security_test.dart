import 'package:flutter_test/flutter_test.dart';
import 'package:stickerdocs_core/src/svg_security.dart';
import 'package:stickerdocs_core/src/utils.dart';

void main() {
  test('Non-well formed XML should be rejected', () async {
    const payload = '''
      <
    ''';

    expect(isSafeSVG(stringToUint8List(payload)), isFalse);
  });

  test('XXE should not be permitted', () async {
    const payload = '''
      <!DOCTYPE foo [
        <!ENTITY xxe SYSTEM "file:///etc/passwd">
      ]>
      <foo>&xxe;</foo>
    ''';

    expect(isSafeSVG(stringToUint8List(payload)), isFalse);
  });

  test('We will not accept any random XML data', () async {
    const payload = '''
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <root><p>Hello</p></root>
    ''';

    expect(isSafeSVG(stringToUint8List(payload)), isFalse);
  });

  test('Legitimate SVG files should be permitted', () async {
    const payloads = [
      '''
      <?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <svg></svg>
    ''',
      '''<svg></svg>'''
    ];

    for (final payload in payloads) {
      expect(isSafeSVG(stringToUint8List(payload)), isTrue);
    }
  });
}
