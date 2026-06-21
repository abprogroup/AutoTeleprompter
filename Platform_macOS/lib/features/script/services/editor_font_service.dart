import 'package:flutter/material.dart';

class EditorFontService {
  static const defaultFamily = 'Inter';

  static const families = <String>[
    'Inter',
    'Roboto',
    'Outfit',
    'Montserrat',
    'Playfair Display',
    'Merriweather',
    'Lora',
    'Courier Prime',
  ];

  static String cleanFamily(String family) {
    final clean = family.trim();
    return clean.isEmpty ? defaultFamily : clean;
  }

  static TextStyle applyFamily(TextStyle style, String family) {
    return style.copyWith(fontFamily: cleanFamily(family));
  }
}
