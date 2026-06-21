import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/remote/services/remote_control_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote command validation accepts only known safe commands', () {
    expect(RemoteControlService.isAllowedCommand('TOGGLE'), isTrue);
    expect(RemoteControlService.isAllowedCommand('RESET'), isTrue);
    expect(RemoteControlService.isAllowedCommand('SET_SPEED:-300'), isTrue);
    expect(RemoteControlService.isAllowedCommand('SET_SPEED:0.5'), isTrue);
    expect(RemoteControlService.isAllowedCommand('SET_SPEED:300'), isTrue);

    expect(RemoteControlService.isAllowedCommand('SET_SPEED:-301'), isFalse);
    expect(RemoteControlService.isAllowedCommand('SET_SPEED:301'), isFalse);
    expect(
        RemoteControlService.isAllowedCommand('SET_SPEED:1;rm -rf /'), isFalse);
    expect(RemoteControlService.isAllowedCommand('UNKNOWN'), isFalse);
  });

  test('debug request logging redacts pairing pins', () {
    final sanitized = RemoteControlService.debugSanitizeRequestTargetForTests(
      '/pair?pin=123456&safe=value',
    );
    final tokenSanitized =
        RemoteControlService.debugSanitizeRequestTargetForTests(
      '/ws?token=session-secret&safe=value',
    );

    expect(sanitized, '/pair?pin=<redacted>&safe=value');
    expect(tokenSanitized, '/ws?token=<redacted>&safe=value');
    expect(sanitized, isNot(contains('123456')));
    expect(tokenSanitized, isNot(contains('session-secret')));
  });

  test('debug text redacts tokens and local paths', () {
    final sanitized = RemoteControlService.debugSanitizeTextForTests(
      'Bearer secret-bearer token=secret-token '
      'client_secret=secret-client /Users/proapple/Desktop/private.json '
      r'C:\Users\localuser\Desktop\private.json',
    );

    expect(sanitized, contains('Bearer <redacted>'));
    expect(sanitized, contains('token=<redacted>'));
    expect(sanitized, contains('client_secret=<redacted>'));
    expect(sanitized, contains('<local-path>'));
    expect(sanitized, isNot(contains('secret-bearer')));
    expect(sanitized, isNot(contains('secret-token')));
    expect(sanitized, isNot(contains('secret-client')));
    expect(sanitized, isNot(contains('/Users/proapple')));
    expect(sanitized, isNot(contains(r'C:\Users\localuser')));
  });

  test('remote port failure message does not expose raw socket details', () {
    final message = RemoteControlService.debugPortsUnavailableMessageForTests();

    expect(message, contains('Unable to start remote control.'));
    expect(message, contains('8080-8090'));
    expect(message, isNot(contains('SocketException')));
    expect(message, isNot(contains('Address already in use')));
    expect(message, isNot(contains('/Users/')));
  });

  test('remote profile names stay unique and removable only when safe', () {
    final service = RemoteControlService();
    addTearDown(service.dispose);

    final primary = service.defaultProfileId;
    final secondary = service.createControllerProfile('Control Booth');

    expect(service.controllerProfiles.map((profile) => profile.name), [
      'Primary remote',
      'Control Booth',
    ]);
    expect(
        service.renameControllerProfile(secondary, 'Primary remote'), isFalse);
    expect(service.renameControllerProfile(secondary, 'Director'), isTrue);
    expect(service.controllerProfiles.map((profile) => profile.name), [
      'Primary remote',
      'Director',
    ]);

    service.removeControllerProfile(primary);
    expect(service.controllerProfiles, hasLength(1));
    service.removeControllerProfile(secondary);
    expect(service.controllerProfiles, hasLength(1));
  });

  test('multiple remote profiles can run and stop independently', () async {
    final service = RemoteControlService();
    addTearDown(service.dispose);

    final primary = service.defaultProfileId;
    final secondary = service.createControllerProfile('Remote 2');

    await service.startControllerProfile(primary);
    await service.startControllerProfile(secondary);

    final profiles = service.controllerProfiles;
    expect(profiles.where((profile) => profile.isRunning), hasLength(2));
    expect(service.remoteUrlForProfile(primary), contains('?pin='));
    expect(service.remoteUrlForProfile(secondary), contains('?pin='));

    await service.stopControllerProfile(primary);
    expect(service.isRunning, isTrue);
    expect(
      service.controllerProfiles
          .singleWhere((profile) => profile.id == primary)
          .isRunning,
      isFalse,
    );
    expect(
      service.controllerProfiles
          .singleWhere((profile) => profile.id == secondary)
          .isRunning,
      isTrue,
    );

    await service.stopControllerProfile(secondary);
    expect(service.isRunning, isFalse);
  });

  test('remote websocket commands follow presenter availability state',
      () async {
    final service = RemoteControlService();
    addTearDown(service.dispose);

    await service.start();
    final token = await _pairToken(service);
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${service.port}/ws?token=$token',
    );
    addTearDown(socket.close);

    final messages = <String>[];
    final subscription = socket.listen(
      (message) => messages.add(message.toString()),
    );
    addTearDown(subscription.cancel);
    await _waitUntil(
      () => messages.any((message) => message.contains('"type":"STATE"')),
      description: 'initial remote state',
    );
    messages.clear();

    final commands = <String>[];
    final commandSubscription = service.onCommand.listen(commands.add);
    addTearDown(commandSubscription.cancel);

    socket.add('RESET');
    await _waitUntil(
      () => messages.any((message) => message.contains('command_unavailable')),
      description: 'inactive presenter command rejection',
    );
    expect(commands, isEmpty);
    messages.clear();

    service.publishPresenterState(
      scriptActive: true,
      sessionActive: false,
      isStarting: false,
      scrollMode: 'auto',
      scrollSpeed: 0,
    );
    socket.add('RESET');
    await _waitUntil(
      () => commands.contains('RESET'),
      description: 'active presenter reset command',
    );
    commands.clear();
    messages.clear();

    service.publishPresenterState(
      scriptActive: true,
      sessionActive: true,
      isStarting: false,
      scrollMode: 'auto',
      scrollSpeed: 0,
    );
    socket.add('BOOKMARK_REMOVE');
    await _waitUntil(
      () => messages.any((message) => message.contains('command_unavailable')),
      description: 'bookmark remove locked during active session',
    );
    expect(commands, isEmpty);
    messages.clear();

    socket.add('TOGGLE');
    await _waitUntil(
      () => commands.contains('TOGGLE'),
      description: 'toggle allowed during active session',
    );
    commands.clear();

    service.publishPresenterState(
      scriptActive: true,
      sessionActive: false,
      isStarting: true,
      scrollMode: 'auto',
      scrollSpeed: 0,
    );
    socket.add('RESET');
    await _waitUntil(
      () => messages.any((message) => message.contains('command_unavailable')),
      description: 'non-toggle command locked while starting',
    );
    expect(commands, isEmpty);
    messages.clear();

    socket.add('TOGGLE');
    await _waitUntil(
      () => commands.contains('TOGGLE'),
      description: 'toggle allowed while starting',
    );
  });
}

Future<String> _pairToken(RemoteControlService service) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
          'http://127.0.0.1:${service.port}/pair?pin=${service.pairingPin}'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['token'] as String;
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String description,
}) async {
  for (var i = 0; i < 50; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $description.');
}
