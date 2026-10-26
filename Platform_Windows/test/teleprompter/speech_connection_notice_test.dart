import 'package:autoteleprompter/features/teleprompter/services/stt_connection_status.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/speech_connection_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final message in [
    SttConnectionStatus.reconnecting,
    SttConnectionStatus.offline,
    SttConnectionStatus.awaitingSpeech,
    SttConnectionStatus.matching,
  ]) {
    testWidgets('visible transient notice: $message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: Column(
                children: [
                  SpeechConnectionNotice(
                    message: message,
                    recoveryColor: Colors.pinkAccent,
                  ),
                  Row(
                    children: [
                      SpeechConnectionBadge(
                        message: message,
                        isListening: true,
                      ),
                      const Expanded(
                        child: LinearProgressIndicator(value: 0.7),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text('MIC READY'), findsNothing);
      expect(find.text(SttConnectionStatus.badge(message)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('recovered notice disappears without hiding microphone meter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SpeechConnectionNotice(message: ''),
              SpeechConnectionBadge(message: '', isListening: true),
              LinearProgressIndicator(value: 0.7),
            ],
          ),
        ),
      ),
    );
    expect(find.text('MIC READY'), findsOneWidget);
    expect(find.textContaining('Reconnecting'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
