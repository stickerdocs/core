import 'dart:typed_data';

import 'package:stickerdocs_core/src/utils.dart';
import 'package:xml/xml.dart';

bool isSafeSVG(Uint8List svg) {
  XmlDocument document;

  try {
    document = XmlDocument.parse(uint8ListToString(svg));
  } catch (e) {
    return false;
  }

  for (var node in document.children) {
    if (node is XmlDoctype) {
      return false;
    }
  }

  return document.rootElement.qualifiedName.toLowerCase() == 'svg';
}
