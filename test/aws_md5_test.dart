import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AWS MD5', () {
    var md5 = 'C9A5A6878D97B48CC965C1E41859F034';
    var expected = 'yaWmh42XtIzJZcHkGFnwNA==';

    var result = base64.encode(hex.decode(md5));

    expect(expected, result);
  });
}
