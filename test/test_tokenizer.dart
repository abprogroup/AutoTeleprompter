import 'package:flutter/material.dart';
import 'lib/features/script/models/script_word.dart';
import 'lib/features/teleprompter/services/word_aligner.dart';

void main() {
  const text = '[center]Hello World[/center]\n[right]Hebrew RTL[/right]';
  final words = WordAligner.tokenize(text);
  
  print('--- DIAL-UP AUDIT: WordAligner ---');
  for (var w in words) {
    print('Word: "${w.raw}" | Align: ${w.alignment} | RTL: ${w.isRtl}');
  }
}
