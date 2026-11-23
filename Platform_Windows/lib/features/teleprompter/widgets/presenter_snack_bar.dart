import 'package:flutter/material.dart';

/// Compact single-line SnackBar for Presenter and Content Creator modes so
/// status/bookmark notifications stay slim at the bottom edge without covering
/// the prompter control buttons.
SnackBar buildCompactPresenterSnackBar(
  String message, {
  Duration duration = const Duration(seconds: 2),
  Color? backgroundColor,
  Color? textColor,
  SnackBarAction? action,
}) {
  return SnackBar(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    backgroundColor: backgroundColor,
    duration: duration,
    action: action,
    content: Text(
      message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.15,
        color: textColor,
      ),
    ),
  );
}
