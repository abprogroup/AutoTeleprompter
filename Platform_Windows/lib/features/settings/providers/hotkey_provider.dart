import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_hotkey.dart';

final hotkeyProvider = StateNotifierProvider<HotkeyNotifier, HotkeyBindings>(
  (ref) => HotkeyNotifier(),
);

/// Separate app-level preferences: never part of a script/profile or cloud sync.
class HotkeyNotifier extends StateNotifier<HotkeyBindings> {
  HotkeyNotifier() : super(HotkeyBindings(loaded: false)) {
    ready = _load();
    _tail = ready;
  }

  static const preferenceKey = 'windowsAppHotkeys.v1';
  late final Future<void> ready;
  late Future<void> _tail;

  Future<void> _load() async {
    var loaded = HotkeyBindings();
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(preferenceKey);
      if (json != null) loaded = HotkeyBindings.fromJson(jsonDecode(json));
    } catch (_) {
      // Malformed or unavailable preferences must not prevent app startup.
    }
    if (mounted) state = loaded;
  }

  Future<String?> setBinding(AppHotkeyAction action, HotkeyBinding? binding) =>
      _enqueue(() async {
        if (binding != null) {
          final invalid = binding.validationError;
          if (invalid != null) return invalid;
          final conflict = state.conflictFor(action, binding);
          if (conflict != null) return 'Already assigned to ${conflict.title}.';
        }
        return _save(state.withBinding(action, binding));
      });

  Future<String?> resetBinding(AppHotkeyAction action) =>
      setBinding(action, HotkeyBindings.defaults[action]);

  Future<String?> resetAll() => _enqueue(() => _save(HotkeyBindings()));

  Future<String?> _enqueue(Future<String?> Function() operation) {
    final next = _tail.then(
      (_) =>
          mounted
              ? operation()
              : Future<String?>.value('Settings page was closed.'),
    );
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<String?> _save(HotkeyBindings updated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        preferenceKey,
        jsonEncode(updated.toJson()),
      );
      if (!saved) return 'Could not save hotkeys. Please try again.';
      if (mounted) state = updated;
      return null;
    } catch (_) {
      return 'Could not save hotkeys. Please try again.';
    }
  }
}
