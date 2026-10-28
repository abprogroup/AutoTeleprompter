import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoteleprompter/features/settings/widgets/cloud_account_connection_actions.dart';

void main() {
  testWidgets(
    'connected account check is separate from reconnect and cancel stays reachable',
    (tester) async {
      var checks = 0, reconnects = 0, cancels = 0;
      Future<void> show({bool busy = false, bool checking = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    CloudAccountConnectionActions(
                      connected: true,
                      signInBusy: busy,
                      checking: checking,
                      onConnect: () => reconnects++,
                      onCheck: () => checks++,
                    ),
                    if (busy) CloudSignInNotice(onCancel: () => cancels++),
                  ],
                ),
              ),
            ),
          );
      await show();
      await tester.tap(find.text('Check connection'));
      expect(checks, 1);
      expect(reconnects, 0);
      await tester.tap(find.text('Reconnect / switch account'));
      expect(reconnects, 1);
      await show(busy: true);
      await tester.tap(find.text('Reconnect / switch account'));
      expect(reconnects, 1);
      await tester.tap(find.text('Cancel sign-in'));
      expect(cancels, 1);
      await show(checking: true);
      await tester.tap(find.text('Checking connection...'));
      expect(checks, 1);
    },
  );

  testWidgets(
    'fresh connection offers connect without pretending it is verified',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudAccountConnectionActions(
              connected: false,
              signInBusy: false,
              checking: false,
              onConnect: () {},
            ),
          ),
        ),
      );
      expect(find.text('Connect account'), findsOneWidget);
      expect(find.text('Check connection'), findsNothing);
    },
  );
}
