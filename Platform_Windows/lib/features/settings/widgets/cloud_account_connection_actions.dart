import 'package:flutter/material.dart';

class CloudAccountConnectionActions extends StatelessWidget {
  const CloudAccountConnectionActions({
    super.key,
    required this.connected,
    required this.signInBusy,
    required this.checking,
    this.onConnect,
    this.onCheck,
  });
  final bool connected;
  final bool signInBusy;
  final bool checking;
  final VoidCallback? onConnect;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (connected)
        ElevatedButton.icon(
          onPressed: checking ? null : onCheck,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(checking ? 'Checking connection...' : 'Check connection'),
        ),
      if (onConnect != null)
        OutlinedButton.icon(
          onPressed: signInBusy || checking ? null : onConnect,
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(
            connected ? 'Reconnect / switch account' : 'Connect account',
          ),
        ),
    ],
  );
}

class CloudSignInNotice extends StatelessWidget {
  const CloudSignInNotice({super.key, required this.onCancel});
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Cloud sign-in is open. Finish in your browser or cancel here.',
          style: TextStyle(color: Colors.white70),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel sign-in')),
      ],
    ),
  );
}
