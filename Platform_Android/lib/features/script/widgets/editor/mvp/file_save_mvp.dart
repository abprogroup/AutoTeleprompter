import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../editor_dialogs.dart';
import '../../../services/docx_service.dart';
import '../../../services/rtf_service.dart';

/// v4.1.1 MVP: File Save System
/// ─────────────────────────────────────────────────────────────────────────────
/// Isolated save/export logic extracted from script_editor_screen.dart.
/// Fixes:
///   Bug #1: Files saved as ".bin" when user removes extension in save dialog.
///   Bug #2: DOCX/RTF formats were saved as raw UTF-8 instead of proper format.
///
/// Responsibilities:
///   - Show format picker dialog
///   - Generate correct bytes for each format (TXT/DOCX/RTF)
///   - Save via FilePicker with proper filename and extension enforcement
///   - Warn user if Android SAF stripped the extension
class FileSaveMvp {
  FileSaveMvp._();

  /// Entry point: show format dialog, generate bytes, save to disk.
  ///
  /// [context] — BuildContext for dialogs and snackbars.
  /// [title] — current script title (used as default filename).
  /// [getText] — callback to get the current full script text.
  static Future<void> saveScript({
    required BuildContext context,
    required String title,
    required String Function() getText,
  }) async {
    // 1. Let user pick format
    final format = await EditorDialogs.showSaveFormatDialog(context);
    if (format == null || !context.mounted) return;

    final text = getText();
    if (text.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nothing to save — script is empty.'),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 2. Generate bytes for the chosen format
    final Uint8List bytes = _generateBytes(text, format);

    // 3. Build safe filename with guaranteed extension
    final safeName = _sanitizeTitle(title, format);
    final fileName = '$safeName.$format';

    // 4. Save via system file picker
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save as ${format.toUpperCase()}',
      fileName: fileName,
      bytes: bytes,
    );

    if (savedPath == null || !context.mounted) return;

    // 5. Extension enforcement — if Android SAF stripped it, try to rename
    if (!savedPath.toLowerCase().endsWith('.$format')) {
      final success = await _tryEnforceExtension(savedPath, format);
      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved as ${format.toUpperCase()} ✓'),
              backgroundColor: Colors.green[700],
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File saved, but the system removed the ".$format" extension. '
                'You may need to rename it manually.',
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  /// Generate the correct byte representation for each format.
  ///
  /// - TXT: raw UTF-8
  /// - DOCX: proper Office Open XML ZIP via DocxService
  /// - RTF: proper Rich Text Format via RtfService
  /// - PDF: UTF-8 fallback (no native PDF generator yet)
  static Uint8List _generateBytes(String text, String format) {
    switch (format.toLowerCase()) {
      case 'docx':
        return Uint8List.fromList(DocxService.generate(text));
      case 'rtf':
        return Uint8List.fromList(RtfService.generate(text));
      case 'txt':
      case 'pdf':
      default:
        return Uint8List.fromList(utf8.encode(text));
    }
  }

  /// Strip unsafe filesystem characters and any prior extension from the title.
  static String _sanitizeTitle(String title, String format) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').replaceAll(
          RegExp(r'\.(txt|pdf|docx|rtf|doc|pages|rtf)$', caseSensitive: false),
          '',
        );
  }

  /// Attempt to rename the file to add the correct extension.
  /// Returns true if successful, false if the path is a content URI or rename fails.
  static Future<bool> _tryEnforceExtension(
      String savedPath, String format) async {
    try {
      // Content URIs (content://...) cannot be renamed via dart:io
      if (savedPath.startsWith('content://')) return false;

      final file = File(savedPath);
      if (!await file.exists()) return false;

      final correctedPath = '$savedPath.$format';
      await file.rename(correctedPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
