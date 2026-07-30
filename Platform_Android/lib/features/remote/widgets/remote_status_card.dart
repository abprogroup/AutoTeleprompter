import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/remote_control_service.dart';

/// Ported verbatim from Windows - note this is unused there too (never
/// instantiated anywhere in Windows' widget tree), kept only for file-tree
/// parity and because a future gallery "remote status" surface may want it.
class RemoteStatusCard extends ConsumerWidget {
  final VoidCallback onOpenSettings;

  const RemoteStatusCard({
    super.key,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteControlProvider);
    final isRunning = remote.isRunning;
    final accent = isRunning ? const Color(0xFFFFBF00) : Colors.white38;
    final runningUrl = isRunning ? remote.preferredUrl() : null;
    final profileCount = remote.controllerProfiles.length;
    final profileLabel =
        profileCount == 1 ? '1 named remote' : '$profileCount named remotes';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenSettings,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRunning
                      ? Icons.settings_remote_rounded
                      : Icons.settings_remote_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local Remote Control',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (runningUrl == null)
                      Text(
                        'Stopped. $profileLabel ready for phones, tablets, or operators.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      )
                    else
                      FutureBuilder<String>(
                        future: runningUrl,
                        builder: (context, snapshot) {
                          final url = snapshot.data ?? remote.localUrl;
                          return Text(
                            'Running at $url - $profileLabel, '
                            '${remote.connectedClientCount} connected',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isRunning)
                Tooltip(
                  message: 'Copy paired remote URL',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final url = await remote.preferredUrl();
                      if (url.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Paired remote URL copied.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: Color(0xFFFFBF00),
                      size: 19,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
