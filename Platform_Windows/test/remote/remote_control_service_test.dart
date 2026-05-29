import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/remote/services/remote_control_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('remote control accepts only known command schema', () {
    const accepted = [
      'TOGGLE',
      'FASTER',
      'SLOWER',
      'RESET',
      'MODE_AUTO',
      'MODE_MANUAL',
    ];

    for (final command in accepted) {
      expect(RemoteControlService.isAllowedCommand(command), isTrue);
    }

    expect(RemoteControlService.isAllowedCommand(''), isFalse);
    expect(RemoteControlService.isAllowedCommand('RESET_ALL'), isFalse);
    expect(RemoteControlService.isAllowedCommand('TOGGLE '), isFalse);
    expect(RemoteControlService.isAllowedCommand(' TOGGLE'), isFalse);
    expect(RemoteControlService.isAllowedCommand('TOGGLE\n'), isFalse);
    expect(RemoteControlService.isAllowedCommand('TOGGLE\nRESET'), isFalse);
    expect(RemoteControlService.isAllowedCommand('{"cmd":"TOGGLE"}'), isFalse);
  });

  test('remote control pairing and page responses use hardened headers',
      () async {
    final service = RemoteControlService();
    addTearDown(service.stop);

    await service.start();
    final client = HttpClient();
    addTearDown(client.close);

    final rootRequest =
        await client.getUrl(Uri.parse('http://localhost:${service.port}/'));
    final rootResponse = await rootRequest.close();
    expect(rootResponse.statusCode, HttpStatus.ok);
    expect(
        rootResponse.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(rootResponse.headers.value('x-content-type-options'), 'nosniff');
    expect(rootResponse.headers.contentType?.mimeType, 'text/html');
    await rootResponse.drain<void>();

    final badPairRequest = await client.getUrl(
      Uri.parse('http://localhost:${service.port}/pair?pin=000000'),
    );
    final badPairResponse = await badPairRequest.close();
    expect(badPairResponse.statusCode, HttpStatus.forbidden);
    expect(badPairResponse.headers.value(HttpHeaders.cacheControlHeader),
        'no-store');
    expect(badPairResponse.headers.value('x-content-type-options'), 'nosniff');
    await badPairResponse.drain<void>();

    final goodPairRequest = await client.getUrl(
      Uri.parse(
        'http://localhost:${service.port}/pair?pin=${service.pairingPin}',
      ),
    );
    final goodPairResponse = await goodPairRequest.close();
    final text = await goodPairResponse.transform(utf8.decoder).join();
    final json = jsonDecode(text) as Map<String, dynamic>;

    expect(goodPairResponse.statusCode, HttpStatus.ok);
    expect(goodPairResponse.headers.value(HttpHeaders.cacheControlHeader),
        'no-store');
    expect(goodPairResponse.headers.value('x-content-type-options'), 'nosniff');
    expect(json['ok'], isTrue);
    expect(json['token'], isA<String>());
    expect((json['token'] as String).length, greaterThanOrEqualTo(24));
  });

  test('remote control websocket accepts paired token and rejects bad commands',
      () async {
    final service = RemoteControlService();
    addTearDown(service.stop);

    await service.start();
    final client = HttpClient();
    addTearDown(client.close);

    final pairRequest = await client.getUrl(
      Uri.parse(
        'http://localhost:${service.port}/pair?pin=${service.pairingPin}',
      ),
    );
    final pairResponse = await pairRequest.close();
    final pairText = await pairResponse.transform(utf8.decoder).join();
    final token =
        (jsonDecode(pairText) as Map<String, dynamic>)['token'] as String;

    final channel = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${service.port}/ws?token=$token'),
    );
    addTearDown(() async => channel.sink.close());

    channel.sink.add('TOGGLE');
    expect(
      await service.onCommand.first.timeout(const Duration(seconds: 2)),
      'TOGGLE',
    );

    channel.sink.add('RESET_ALL');
    final response = await channel.stream
        .firstWhere((message) => message.toString().contains('invalid_command'))
        .timeout(const Duration(seconds: 2));

    expect(response.toString(), contains('invalid_command'));
  });

  test('remote control websocket rejects an unpaired token', () async {
    final service = RemoteControlService();
    addTearDown(service.stop);

    await service.start();
    final client = HttpClient();
    addTearDown(client.close);

    final request = await client.getUrl(
      Uri.parse('http://localhost:${service.port}/ws?token=bad-token'),
    );
    request.headers.set(HttpHeaders.connectionHeader, 'Upgrade');
    request.headers.set(HttpHeaders.upgradeHeader, 'websocket');
    request.headers.set('sec-websocket-key', 'dGhlIHNhbXBsZSBub25jZQ==');
    request.headers.set('sec-websocket-version', '13');

    final response = await request.close();
    expect(response.statusCode, HttpStatus.forbidden);
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(response.headers.value('x-content-type-options'), 'nosniff');
    await response.drain<void>();
  });
}
