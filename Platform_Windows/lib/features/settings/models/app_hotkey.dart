import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum AppHotkeyAction {
  enterFullscreen,
  exitFullscreen,
  searchScript,
  previousBookmark,
  nextBookmark,
  toggleBookmark,
}

extension AppHotkeyActionInfo on AppHotkeyAction {
  String get title => switch (this) {
    AppHotkeyAction.enterFullscreen => 'Enter fullscreen',
    AppHotkeyAction.exitFullscreen => 'Exit fullscreen',
    AppHotkeyAction.searchScript => 'Search script',
    AppHotkeyAction.previousBookmark => 'Previous bookmark',
    AppHotkeyAction.nextBookmark => 'Next bookmark',
    AppHotkeyAction.toggleBookmark => 'Add / remove bookmark',
  };

  String get description => switch (this) {
    AppHotkeyAction.enterFullscreen => 'Present mode only',
    AppHotkeyAction.exitFullscreen => 'Present mode; Escape also exits',
    AppHotkeyAction.searchScript => 'Editor and Present mode',
    AppHotkeyAction.previousBookmark => 'Editor and Present mode; requires Pro',
    AppHotkeyAction.nextBookmark => 'Editor and Present mode; requires Pro',
    AppHotkeyAction.toggleBookmark =>
      'At the editor cursor or presenter reading position; requires Pro',
  };
}

/// App commands only. Typing/navigation keep their native behavior while editing.
@immutable
class HotkeyBinding {
  const HotkeyBinding(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  static HotkeyBinding? fromEvent(KeyEvent event) {
    if (event is! KeyDownEvent || event.synthesized) return null;
    final keyboard = HardwareKeyboard.instance;
    if (LogicalKeyboardKey.collapseSynonyms({event.logicalKey}).any(
      (key) => const [
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.alt,
        LogicalKeyboardKey.meta,
      ].contains(key),
    )) {
      return null;
    }
    return HotkeyBinding(
      event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  bool get isFunctionKey =>
      key.keyId >= LogicalKeyboardKey.f1.keyId &&
      key.keyId <= LogicalKeyboardKey.f24.keyId;

  bool get isNavigationKey => const [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  ].contains(key);

  String? get validationError {
    if (key == LogicalKeyboardKey.escape) {
      return 'Escape is reserved for closing dialogs and exiting fullscreen.';
    }
    final isLetter =
        key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId;
    final isDigit =
        key.keyId >= LogicalKeyboardKey.digit0.keyId &&
        key.keyId <= LogicalKeyboardKey.digit9.keyId;
    if (!isFunctionKey && !isNavigationKey && !(isLetter || isDigit)) {
      return 'Use a letter, number, function key, arrow, Home, End or Page key.';
    }
    if (meta) return 'Windows-key combinations are reserved for Windows.';
    if (control && alt && !isFunctionKey && !isNavigationKey) {
      return 'Ctrl+Alt is reserved for keyboard-language characters (AltGr).';
    }
    if (key == LogicalKeyboardKey.f4 && (control || alt)) {
      return 'This combination is reserved for closing windows.';
    }
    if (control &&
        const [
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyZ,
          LogicalKeyboardKey.keyY,
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.keyI,
          LogicalKeyboardKey.keyU,
          LogicalKeyboardKey.keyO,
          LogicalKeyboardKey.keyS,
          LogicalKeyboardKey.keyP,
          LogicalKeyboardKey.keyN,
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.keyQ,
        ].contains(key)) {
      return 'This combination is reserved for standard editing commands.';
    }
    return null;
  }

  String get label => [
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (meta) 'Win',
    key.keyLabel.toUpperCase(),
  ].join('+');

  Map<String, Object> toJson() => {
    'key': key.keyId,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  static HotkeyBinding? fromJson(Object? json) {
    if (json is! Map || json['key'] is! int) return null;
    for (final modifier in ['control', 'alt', 'shift', 'meta']) {
      if (json[modifier] != null && json[modifier] is! bool) return null;
    }
    final key = LogicalKeyboardKey.findKeyByKeyId(json['key'] as int);
    if (key == null) return null;
    final result = HotkeyBinding(
      key,
      control: json['control'] == true,
      alt: json['alt'] == true,
      shift: json['shift'] == true,
      meta: json['meta'] == true,
    );
    return result.validationError == null ? result : null;
  }

  @override
  bool operator ==(Object other) =>
      other is HotkeyBinding &&
      key == other.key &&
      control == other.control &&
      alt == other.alt &&
      shift == other.shift &&
      meta == other.meta;
  @override
  int get hashCode => Object.hash(key, control, alt, shift, meta);
}

@immutable
class HotkeyBindings {
  HotkeyBindings({
    Map<AppHotkeyAction, HotkeyBinding?>? bindings,
    this.loaded = true,
  }) : _bindings = Map.unmodifiable(bindings ?? defaults);

  final Map<AppHotkeyAction, HotkeyBinding?> _bindings;
  final bool loaded;
  static const defaults = <AppHotkeyAction, HotkeyBinding?>{
    AppHotkeyAction.enterFullscreen: HotkeyBinding(LogicalKeyboardKey.f5),
    AppHotkeyAction.exitFullscreen: HotkeyBinding(LogicalKeyboardKey.f3),
    AppHotkeyAction.searchScript: HotkeyBinding(
      LogicalKeyboardKey.keyF,
      control: true,
      shift: true,
    ),
    AppHotkeyAction.previousBookmark: HotkeyBinding(LogicalKeyboardKey.f6),
    AppHotkeyAction.nextBookmark: HotkeyBinding(LogicalKeyboardKey.f7),
    AppHotkeyAction.toggleBookmark: HotkeyBinding(LogicalKeyboardKey.f8),
  };

  HotkeyBinding? bindingFor(AppHotkeyAction action) => _bindings[action];
  String labelFor(AppHotkeyAction action) => bindingFor(action)?.label ?? 'Off';
  bool isDefault(AppHotkeyAction action) =>
      _bindings[action] == defaults[action];

  AppHotkeyAction? conflictFor(AppHotkeyAction action, HotkeyBinding binding) {
    for (final other in AppHotkeyAction.values) {
      if (other != action && bindingFor(other) == binding) return other;
    }
    return null;
  }

  HotkeyBindings withBinding(AppHotkeyAction action, HotkeyBinding? binding) =>
      HotkeyBindings(bindings: {..._bindings, action: binding});

  AppHotkeyAction? actionFor(KeyEvent event, {bool editingText = false}) {
    if (!loaded) return null;
    final binding = HotkeyBinding.fromEvent(event);
    if (binding == null || binding.validationError != null) return null;
    // Standalone keys are useful in Present or when the editor is not editing.
    // While typing/selecting, never consume characters or caret navigation.
    if (editingText &&
        (binding.isNavigationKey ||
            (!binding.isFunctionKey &&
                !binding.control &&
                !binding.alt &&
                !binding.meta))) {
      return null;
    }
    for (final action in AppHotkeyAction.values) {
      if (bindingFor(action) == binding) return action;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'bindings': {
      for (final action in AppHotkeyAction.values)
        action.name: bindingFor(action)?.toJson(),
    },
  };

  static HotkeyBindings fromJson(Object? json) {
    if (json is! Map || json['version'] != 1 || json['bindings'] is! Map) {
      return HotkeyBindings();
    }
    final values = json['bindings'] as Map;
    final bindings = {...defaults};
    for (final action in AppHotkeyAction.values) {
      if (!values.containsKey(action.name)) continue;
      final value = values[action.name];
      if (value == null) {
        bindings[action] = null;
      } else {
        final parsed = HotkeyBinding.fromJson(value);
        if (parsed != null) bindings[action] = parsed;
      }
    }
    final result = HotkeyBindings(bindings: bindings);
    for (final action in AppHotkeyAction.values) {
      final binding = bindings[action];
      if (binding != null && result.conflictFor(action, binding) != null) {
        // Ambiguous saved commands must never dispatch an arbitrary winner.
        return HotkeyBindings();
      }
    }
    return result;
  }
}
