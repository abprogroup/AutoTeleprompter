import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'remote_control_service_html.dart';

class RemoteControllerProfile {
  final String id;
  final String name;
  final bool isRunning;
  final String pairingPin;
  final int connectedClientCount;
  final DateTime? sessionTokenExpiresAt;

  const RemoteControllerProfile({
    required this.id,
    required this.name,
    required this.isRunning,
    required this.pairingPin,
    required this.connectedClientCount,
    required this.sessionTokenExpiresAt,
  });
}

class _RemoteControllerProfileState {
  final String id;
  String name;
  bool isRunning = false;
  String pairingPin = '';
  String sessionToken = '';
  DateTime? sessionTokenExpiresAt;

  _RemoteControllerProfileState({
    required this.id,
    required this.name,
  });
}

class RemoteControlService extends ChangeNotifier {
  static const int defaultPort = 8080;
  static const int maxFallbackPort = 8090;
  static const Duration defaultSessionTokenLifetime = Duration(hours: 4);
  static const String _profilesPrefsKey = 'remoteControl.profiles.v1';
  static const Set<String> allowedCommands = {
    'TOGGLE',
    'FASTER',
    'SLOWER',
    'RESET',
    'MODE_AUTO',
    'MODE_MANUAL',
    'BOOKMARK_ADD',
    'BOOKMARK_REMOVE',
    'BOOKMARK_PREVIOUS',
    'BOOKMARK_NEXT',
    'INVERT_COLORS',
  };
  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };
  static const Map<String, String> _htmlHeaders = {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };
  static const Map<String, String> _textHeaders = {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };

  HttpServer? _server;
  final _onCommand = StreamController<String>.broadcast();
  final Set<WebSocketChannel> _clients = <WebSocketChannel>{};
  final Map<WebSocketChannel, String> _clientProfileIds =
      <WebSocketChannel, String>{};
  final Map<String, _RemoteControllerProfileState> _profiles =
      <String, _RemoteControllerProfileState>{};
  final Duration _sessionTokenLifetime;
  final DateTime Function() _clock;
  final bool _persistProfilesEnabled;
  String _defaultProfileId = '';
  int _profileCounter = 0;
  bool _disposed = false;
  bool _presenterScriptActive = false;
  bool _presenterSessionActive = false;
  bool _presenterIsStarting = false;
  String _presenterScrollMode = 'auto';
  String _lastPresenterStateJson = jsonEncode({
    'type': 'STATE',
    'scriptActive': false,
    'sessionActive': false,
    'isStarting': false,
    'scrollMode': 'auto',
    'scrollSpeed': 0.0,
  });

  RemoteControlService({
    Duration sessionTokenLifetime = defaultSessionTokenLifetime,
    DateTime Function()? clock,
    bool persistProfiles = false,
  })  : _sessionTokenLifetime = sessionTokenLifetime,
        _clock = clock ?? DateTime.now,
        _persistProfilesEnabled = persistProfiles;

  Stream<String> get onCommand => _onCommand.stream;
  bool get isRunning => _server != null && _profiles.values.any(_isActive);
  int get port => _server?.port ?? defaultPort;
  String get defaultProfileId {
    _ensureDefaultProfile();
    return _defaultProfileId;
  }

  String get pairingPin =>
      _defaultProfile.isRunning ? _defaultProfile.pairingPin : '';
  String get localUrl => _remoteUrlForHost('localhost');
  int get connectedClientCount => _clients.length;
  DateTime? get sessionTokenExpiresAt =>
      _defaultProfile.isRunning ? _defaultProfile.sessionTokenExpiresAt : null;
  List<RemoteControllerProfile> get controllerProfiles {
    _ensureDefaultProfile();
    return _profiles.values.map((profile) {
      return RemoteControllerProfile(
        id: profile.id,
        name: profile.name,
        isRunning: profile.isRunning,
        pairingPin: profile.isRunning ? profile.pairingPin : '',
        connectedClientCount: _connectedClientCountFor(profile.id),
        sessionTokenExpiresAt:
            profile.isRunning ? profile.sessionTokenExpiresAt : null,
      );
    }).toList(growable: false);
  }

  _RemoteControllerProfileState get _defaultProfile {
    _ensureDefaultProfile();
    return _profiles[_defaultProfileId]!;
  }

  Future<void> loadSavedProfiles() async {
    if (!_persistProfilesEnabled || isRunning) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _ensureDefaultProfile();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final savedProfiles = decoded['profiles'];
      if (savedProfiles is! List || savedProfiles.isEmpty) return;

      final nextProfiles = <String, _RemoteControllerProfileState>{};
      var maxCounter =
          decoded['counter'] is int ? decoded['counter'] as int : 0;
      for (final item in savedProfiles) {
        if (item is! Map<String, dynamic>) continue;
        final id = (item['id'] as String?)?.trim();
        final rawName = _cleanProfileName(item['name'] as String?);
        if (id == null || id.isEmpty) continue;
        final name = rawName == null
            ? _nextAvailableProfileName(nextProfiles.values.map((p) => p.name))
            : _uniqueProfileName(
                rawName,
                nextProfiles.values.map((p) => p.name),
              );
        nextProfiles[id] = _RemoteControllerProfileState(id: id, name: name);
        final suffix = int.tryParse(id.replaceFirst('remote_', ''));
        if (suffix != null && suffix > maxCounter) maxCounter = suffix;
      }
      if (nextProfiles.isEmpty) return;

      _profiles
        ..clear()
        ..addAll(nextProfiles);
      final savedDefault = (decoded['defaultId'] as String?)?.trim();
      _defaultProfileId =
          savedDefault != null && _profiles.containsKey(savedDefault)
              ? savedDefault
              : _profiles.keys.first;
      _profileCounter = maxCounter;
      _notifyChanged();
    } catch (error, stack) {
      if (kDebugMode) {
        final safeError = debugSanitizeTextForTests(error.toString());
        final safeStack = debugSanitizeTextForTests(stack.toString());
        debugPrint('Remote profiles could not load: $safeError\n$safeStack');
      }
    }
  }

  Future<void> start() => startControllerProfile(defaultProfileId);

  Future<void> startControllerProfile(String profileId) async {
    _ensureDefaultProfile();
    final profile = _profiles[profileId];
    if (profile == null) return;
    await _ensureServerStarted();
    if (!profile.isRunning) {
      profile.isRunning = true;
      _resetProfileSession(profile);
      _notifyChanged();
    }
  }

  Future<void> _ensureServerStarted() async {
    if (_server != null) return;
    _ensureDefaultProfile();

    final router = Router();
    Handler wsHandlerFor(String profileId) {
      return webSocketHandler((WebSocketChannel webSocket) {
        _clients.add(webSocket);
        _clientProfileIds[webSocket] = profileId;
        webSocket.sink.add(_lastPresenterStateJson);
        _notifyChanged();
        var removed = false;
        void removeClient() {
          if (removed) return;
          removed = true;
          _clients.remove(webSocket);
          _clientProfileIds.remove(webSocket);
          _notifyChanged();
        }

        webSocket.stream.listen((message) {
          final command = message.toString();
          if (!isAllowedCommand(command)) {
            if (kDebugMode) debugPrint('Rejected remote command: $command');
            webSocket.sink.add(
              jsonEncode({'ok': false, 'error': 'invalid_command'}),
            );
            return;
          }
          if (!_isUsableCommand(command)) {
            if (kDebugMode) {
              debugPrint('Rejected unusable remote command: $command');
            }
            webSocket.sink.add(
              jsonEncode({'ok': false, 'error': 'command_unavailable'}),
            );
            return;
          }
          if (kDebugMode) debugPrint('Remote Command: $command');
          _onCommand.add(command);
        }, onDone: removeClient, onError: (_) => removeClient());
      });
    }

    router.get('/pair', (Request request) {
      final pin = request.url.queryParameters['pin'] ?? '';
      final profile = _profileForPin(pin);
      if (profile == null) {
        return Response.forbidden(
          jsonEncode({'ok': false, 'error': 'pairing_required'}),
          headers: _jsonHeaders,
        );
      }
      if (profile.sessionToken.isEmpty || _isSessionExpired(profile)) {
        _renewProfileToken(profile);
      }
      return Response.ok(
        jsonEncode({
          'ok': true,
          'token': profile.sessionToken,
          'remoteId': profile.id,
          'remoteName': profile.name,
          'expiresAt': profile.sessionTokenExpiresAt?.toIso8601String(),
        }),
        headers: _jsonHeaders,
      );
    });

    router.get('/ws', (Request request) {
      final token = request.url.queryParameters['token'] ?? '';
      final profile = _profileForToken(token);
      if (profile == null) {
        return Response.forbidden('Pairing required.', headers: _textHeaders);
      }
      return wsHandlerFor(profile.id)(request);
    });

    router.get('/', (Request request) {
      return Response.ok(remoteControlHtml, headers: _htmlHeaders);
    });

    final pipeline = kDebugMode
        ? const Pipeline().addMiddleware(_sanitizedLogRequests())
        : const Pipeline();
    final handler = pipeline.addHandler(router.call);

    _server = await _bindAvailablePort(handler);
    _notifyChanged();
    if (kDebugMode) {
      debugPrint(
        'Remote server active at http://${_server!.address.address}:$port',
      );
    }
  }

  Future<HttpServer> _bindAvailablePort(Handler handler) async {
    Object? lastError;
    for (var candidate = defaultPort;
        candidate <= maxFallbackPort;
        candidate++) {
      try {
        return await io.serve(handler, InternetAddress.anyIPv4, candidate);
      } on SocketException catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint(
            'Remote port $candidate unavailable, trying ${candidate + 1}...',
          );
        }
      }
    }
    throw StateError(
      'Unable to start remote control. Ports '
      '$defaultPort-$maxFallbackPort are unavailable. Last error: $lastError',
    );
  }

  Future<String> preferredUrl() async {
    return preferredUrlForProfile(_defaultProfileId);
  }

  Future<String> preferredUrlForProfile(String profileId) async {
    final addresses = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in addresses) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return _remoteUrlForHost(address.address, profileId: profileId);
        }
      }
    }
    return remoteUrlForProfile(profileId);
  }

  void publishPresenterState({
    required bool scriptActive,
    required bool sessionActive,
    required bool isStarting,
    required String scrollMode,
    required double scrollSpeed,
  }) {
    final normalizedMode = scrollMode == 'manual' ? 'manual' : 'auto';
    final normalizedSpeed = scrollSpeed.clamp(-300.0, 300.0).toDouble();
    _presenterScriptActive = scriptActive;
    _presenterSessionActive = sessionActive;
    _presenterIsStarting = isStarting;
    _presenterScrollMode = normalizedMode;
    final next = jsonEncode({
      'type': 'STATE',
      'scriptActive': scriptActive,
      'sessionActive': sessionActive,
      'isStarting': isStarting,
      'scrollMode': normalizedMode,
      'scrollSpeed': normalizedSpeed,
    });
    if (next == _lastPresenterStateJson) return;
    _lastPresenterStateJson = next;
    for (final client in List<WebSocketChannel>.from(_clients)) {
      try {
        client.sink.add(next);
      } catch (_) {
        _clients.remove(client);
        _clientProfileIds.remove(client);
      }
    }
  }

  Future<void> stop() async {
    _closeClients();
    await _server?.close();
    _server = null;
    for (final profile in _profiles.values) {
      profile.isRunning = false;
      profile.pairingPin = '';
      profile.sessionToken = '';
      profile.sessionTokenExpiresAt = null;
    }
    _notifyChanged();
  }

  Future<void> stopControllerProfile(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) return;
    _closeClientsForProfile(profileId);
    profile.isRunning = false;
    profile.pairingPin = '';
    profile.sessionToken = '';
    profile.sessionTokenExpiresAt = null;
    if (!_profiles.values.any(_isActive)) {
      await _server?.close();
      _server = null;
    }
    _notifyChanged();
  }

  Future<void> revokeSession() async {
    if (!isRunning) return;
    _closeClients();
    for (final profile in _profiles.values) {
      if (profile.isRunning) _resetProfileSession(profile);
    }
    _notifyChanged();
  }

  Future<void> revokeControllerProfile(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null || !profile.isRunning) return;
    _closeClientsForProfile(profileId);
    _resetProfileSession(profile);
    _notifyChanged();
  }

  String createControllerProfile([String? name]) {
    final id = 'remote_${++_profileCounter}';
    final firstProfile = _profiles.isEmpty;
    final cleanName = _cleanProfileName(name);
    final profile = _RemoteControllerProfileState(
      id: id,
      name: cleanName != null && isProfileNameAvailable(cleanName)
          ? cleanName
          : nextAvailableProfileName(),
    );
    _profiles[id] = profile;
    if (firstProfile) {
      _defaultProfileId = id;
    }
    _persistProfiles();
    _notifyChanged();
    return id;
  }

  bool renameControllerProfile(String profileId, String name) {
    final profile = _profiles[profileId];
    final clean = _cleanProfileName(name);
    if (profile == null || clean == null) return false;
    if (!isProfileNameAvailable(clean, exceptProfileId: profileId)) {
      return false;
    }
    profile.name = clean;
    _persistProfiles();
    _notifyChanged();
    return true;
  }

  Future<void> removeControllerProfile(String profileId) async {
    if (_profiles.length <= 1 || !_profiles.containsKey(profileId)) return;
    _closeClientsForProfile(profileId);
    _profiles.remove(profileId);
    if (_defaultProfileId == profileId) {
      _defaultProfileId = _profiles.keys.first;
    }
    if (!_profiles.values.any(_isActive)) {
      await _server?.close();
      _server = null;
    }
    _persistProfiles();
    _notifyChanged();
  }

  String remoteUrlForProfile(String profileId) {
    return _remoteUrlForHost('localhost', profileId: profileId);
  }

  bool hasControllerProfile(String profileId) {
    _ensureDefaultProfile();
    return _profiles.containsKey(profileId);
  }

  String nextAvailableProfileName() {
    _ensureDefaultProfile();
    return _nextAvailableProfileName(_profiles.values.map((p) => p.name));
  }

  bool isProfileNameAvailable(String name, {String? exceptProfileId}) {
    final clean = _cleanProfileName(name);
    if (clean == null) return false;
    final normalized = _normalizeProfileName(clean);
    for (final profile in _profiles.values) {
      if (profile.id == exceptProfileId) continue;
      if (_normalizeProfileName(profile.name) == normalized) return false;
    }
    return true;
  }

  String _remoteUrlForHost(String host, {String? profileId}) {
    final base = 'http://$host:$port';
    final profile = _profiles[profileId ?? _defaultProfileId];
    if (profile == null || !profile.isRunning || profile.pairingPin.isEmpty) {
      return base;
    }
    return '$base?pin=${profile.pairingPin}';
  }

  String _newPairingPin() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  String _newSessionToken() {
    final random = Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  void _resetProfileSession(_RemoteControllerProfileState profile) {
    profile.pairingPin = _newPairingPin();
    _renewProfileToken(profile);
  }

  void _renewProfileToken(_RemoteControllerProfileState profile) {
    profile.sessionToken = _newSessionToken();
    profile.sessionTokenExpiresAt = _clock().add(_sessionTokenLifetime);
    _notifyChanged();
  }

  bool _isSessionExpired(_RemoteControllerProfileState profile) {
    final expiresAt = profile.sessionTokenExpiresAt;
    return expiresAt == null || !_clock().isBefore(expiresAt);
  }

  static Middleware _sanitizedLogRequests() {
    return (Handler innerHandler) {
      return (Request request) async {
        final started = DateTime.now();
        try {
          final response = await Future<Response>.sync(
            () => innerHandler(request),
          );
          _debugLogRequest(request, response.statusCode, started);
          return response;
        } catch (_) {
          _debugLogRequest(request, 500, started);
          rethrow;
        }
      };
    };
  }

  @visibleForTesting
  static String debugSanitizeRequestTargetForTests(String target) {
    return debugSanitizeTextForTests(target);
  }

  @visibleForTesting
  static String debugSanitizeTextForTests(String text) {
    var sanitized = text.replaceAllMapped(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      (_) => 'Bearer <redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'([?&](?:pin|token|access_token|refresh_token|client_secret|password)=)'
        r'[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'''\b(access_token|refresh_token|client_secret|password|apikey|api_key|authorization|pin|token)\s*[:=]\s*["']?[^"',}&\s]+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'(/Users/|/private/var/|/var/folders/)[^\s,;)\]}]+',
        caseSensitive: false,
      ),
      '<local-path>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'[A-Z]:\\Users\\[^ \t\r\n,;)\]}]+', caseSensitive: false),
      '<local-path>',
    );
    return sanitized;
  }

  static void _debugLogRequest(
    Request request,
    int statusCode,
    DateTime started,
  ) {
    final elapsed = DateTime.now().difference(started);
    final target = request.url.toString();
    final path = target.isEmpty ? '/' : '/$target';
    final safePath = debugSanitizeRequestTargetForTests(path);
    debugPrint(
      '${DateTime.now().toIso8601String()}  $elapsed ${request.method}'
      '     [$statusCode] $safePath',
    );
  }

  _RemoteControllerProfileState? _profileForPin(String pin) {
    if (pin.isEmpty) return null;
    for (final profile in _profiles.values) {
      if (profile.isRunning && profile.pairingPin == pin) return profile;
    }
    return null;
  }

  _RemoteControllerProfileState? _profileForToken(String token) {
    if (token.isEmpty) return null;
    for (final profile in _profiles.values) {
      if (profile.isRunning &&
          profile.sessionToken == token &&
          !_isSessionExpired(profile)) {
        return profile;
      }
    }
    return null;
  }

  int _connectedClientCountFor(String profileId) {
    return _clientProfileIds.values.where((id) => id == profileId).length;
  }

  void _closeClients() {
    for (final client in List<WebSocketChannel>.from(_clients)) {
      unawaited(client.sink.close());
    }
    _clients.clear();
    _clientProfileIds.clear();
  }

  void _closeClientsForProfile(String profileId) {
    final clients = _clientProfileIds.entries
        .where((entry) => entry.value == profileId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final client in clients) {
      unawaited(client.sink.close());
      _clients.remove(client);
      _clientProfileIds.remove(client);
    }
  }

  void _ensureDefaultProfile() {
    if (_profiles.isEmpty) {
      createControllerProfile('Primary remote');
      return;
    }
    if (_defaultProfileId.isEmpty ||
        !_profiles.containsKey(_defaultProfileId)) {
      _defaultProfileId = _profiles.keys.first;
    }
  }

  bool _isActive(_RemoteControllerProfileState profile) {
    return profile.isRunning;
  }

  String? _cleanProfileName(String? name) {
    final clean = name?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean.length <= 32 ? clean : clean.substring(0, 32);
  }

  String _normalizeProfileName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _nextAvailableProfileName(Iterable<String> names) {
    final used = names.map(_normalizeProfileName).toSet();
    for (var index = 1; index < 1000; index++) {
      final candidate = 'Remote $index';
      if (!used.contains(_normalizeProfileName(candidate))) {
        return candidate;
      }
    }
    return 'Remote ${used.length + 1}';
  }

  String _uniqueProfileName(String desired, Iterable<String> names) {
    final used = names.map(_normalizeProfileName).toSet();
    if (!used.contains(_normalizeProfileName(desired))) return desired;
    return _nextAvailableProfileName(names);
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  void _persistProfiles() {
    if (!_persistProfilesEnabled) return;
    unawaited(_writeProfiles());
  }

  Future<void> _writeProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'counter': _profileCounter,
      'defaultId': _defaultProfileId,
      'profiles': [
        for (final profile in _profiles.values)
          {
            'id': profile.id,
            'name': profile.name,
          },
      ],
    };
    await prefs.setString(_profilesPrefsKey, jsonEncode(data));
  }

  @visibleForTesting
  Future<void> persistProfilesForTest() async {
    if (_persistProfilesEnabled) await _writeProfiles();
  }

  static bool isAllowedCommand(String command) {
    if (allowedCommands.contains(command)) return true;
    final speedMatch = RegExp(r'^SET_SPEED:-?\d{1,3}(?:\.\d+)?$');
    if (!speedMatch.hasMatch(command)) return false;
    final value = double.tryParse(command.substring('SET_SPEED:'.length));
    return value != null && value >= -300 && value <= 300;
  }

  bool _isUsableCommand(String command) {
    if (!_presenterScriptActive) return false;
    if (_presenterIsStarting && command != 'TOGGLE') return false;
    if (command.startsWith('SET_SPEED:')) {
      return _presenterScrollMode == 'manual';
    }
    if (command == 'FASTER' || command == 'SLOWER') {
      return _presenterScrollMode == 'manual';
    }
    if (command == 'BOOKMARK_REMOVE') {
      return !_presenterSessionActive;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _closeClients();
    unawaited(_server?.close());
    _server = null;
    _onCommand.close();
    super.dispose();
  }
}

final remoteControlProvider = ChangeNotifierProvider((ref) {
  final service = RemoteControlService(persistProfiles: true);
  unawaited(service.loadSavedProfiles());
  return service;
});
