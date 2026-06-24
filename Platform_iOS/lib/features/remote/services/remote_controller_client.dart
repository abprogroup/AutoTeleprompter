import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection lifecycle for the in-app remote controller.
enum RemoteControllerStatus { idle, connecting, connected, error }

/// In-app controller client: lets this device drive another device that is
/// hosting the AutoTeleprompter remote server on the same Wi-Fi. It mirrors the
/// browser controller protocol — `GET /pair?pin=` to exchange the PIN for a
/// session token, then a `ws://host/ws?token=` socket that carries plain
/// command strings and receives presenter STATE JSON.
class RemoteControllerClient extends ChangeNotifier {
  RemoteControllerStatus _status = RemoteControllerStatus.idle;
  String _message = '';
  String _remoteName = '';
  Map<String, dynamic> _presenterState = const {};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  RemoteControllerStatus get status => _status;
  String get message => _message;
  String get remoteName => _remoteName;
  Map<String, dynamic> get presenterState => _presenterState;
  bool get isConnected => _status == RemoteControllerStatus.connected;

  /// Connects to a host. [target] may be the full URL the host shows (e.g.
  /// `http://192.168.1.5:8080?pin=123456`) or just `http://192.168.1.5:8080`.
  /// [pinOverride] takes priority over any `pin` query in [target].
  Future<bool> connect({
    required String target,
    String pinOverride = '',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await disconnect();
    final parsed = _parseTarget(target, pinOverride);
    if (parsed == null) {
      _fail('Enter a valid host URL like http://192.168.0.10:8080.');
      return false;
    }
    final (base, pin) = parsed;
    if (pin.isEmpty) {
      _fail('Enter the 6-digit PIN shown on the hosting device.');
      return false;
    }

    _status = RemoteControllerStatus.connecting;
    _message = 'Pairing with ${base.host}…';
    notifyListeners();

    final httpClient = HttpClient();
    try {
      final pairUri = base.replace(
        path: '/pair',
        queryParameters: {'pin': pin},
      );
      final request = await httpClient.getUrl(pairUri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != 200) {
        _fail('Pairing rejected (HTTP ${response.statusCode}). Check the PIN.');
        return false;
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        _fail('Pairing failed. The PIN may be wrong or revoked.');
        return false;
      }
      final token = decoded['token']?.toString() ?? '';
      if (token.isEmpty) {
        _fail('Host did not return a session token.');
        return false;
      }
      _remoteName = decoded['remoteName']?.toString() ?? base.host;

      final wsUri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'token': token},
      );
      final channel = WebSocketChannel.connect(wsUri);
      await channel.ready.timeout(timeout);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _fail('Connection lost.'),
        onDone: _onDone,
      );
      _status = RemoteControllerStatus.connected;
      _message = 'Connected to $_remoteName.';
      notifyListeners();
      return true;
    } on TimeoutException {
      _fail('Connection timed out. Confirm both devices share the Wi-Fi.');
      return false;
    } catch (error) {
      _fail('Could not connect to the host device.');
      if (kDebugMode) debugPrint('Remote controller connect error: $error');
      return false;
    } finally {
      httpClient.close(force: true);
    }
  }

  /// Sends a command string (e.g. TOGGLE, FASTER, RESET, BOOKMARK_NEXT).
  bool sendCommand(String command) {
    final channel = _channel;
    if (channel == null || _status != RemoteControllerStatus.connected) {
      return false;
    }
    channel.sink.add(command);
    return true;
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (_status != RemoteControllerStatus.error) {
      _status = RemoteControllerStatus.idle;
      _message = '';
    }
    _presenterState = const {};
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map<String, dynamic>) {
        if (decoded['type'] == 'STATE') {
          _presenterState = decoded;
          notifyListeners();
        }
      }
    } catch (_) {
      // Non-JSON acknowledgements are ignored.
    }
  }

  void _onDone() {
    if (_status == RemoteControllerStatus.connected) {
      _status = RemoteControllerStatus.idle;
      _message = 'Disconnected from $_remoteName.';
      notifyListeners();
    }
  }

  void _fail(String message) {
    _status = RemoteControllerStatus.error;
    _message = message;
    notifyListeners();
  }

  (Uri, String)? _parseTarget(String target, String pinOverride) {
    var text = target.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : 8080;
    final pin = pinOverride.trim().isNotEmpty
        ? pinOverride.trim()
        : (uri.queryParameters['pin']?.trim() ?? '');
    final base = Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: port,
    );
    return (base, pin);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
