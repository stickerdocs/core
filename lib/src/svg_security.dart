import 'dart:typed_data';

import 'package:stickerdocs_core/src/utils.dart';
import 'package:xml/xml.dart';

bool isSafeSVG(Uint8List svgData) {
  // Max size of 5MB
  if (svgData.length > 5242880) {
    return false;
  }

  XmlDocument document;

  try {
    document = XmlDocument.parse(uint8ListToString(svgData));
  } catch (e) {
    return false;
  }

  for (final node in document.children) {
    if (node is XmlDoctype) {
      return false;
    }
  }

  return document.rootElement.qualifiedName.toLowerCase() == 'svg';
}
