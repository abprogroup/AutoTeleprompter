import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/settings/services/cloud_oauth_service.dart';
import '../services/connection_maintenance.dart';

class ConnectionLifecycle extends ConsumerStatefulWidget {
  const ConnectionLifecycle({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ConnectionLifecycle> createState() =>
      _ConnectionLifecycleState();
}

class _ConnectionLifecycleState extends ConsumerState<ConnectionLifecycle>
    with WidgetsBindingObserver {
  late final ConnectionMaintenance _maintenance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maintenance = ConnectionMaintenance([
      () => ref.read(authProvider.notifier).maintainConnection(),
      CloudOAuthService().maintainConnections,
    ])..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maintenance.checkNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maintenance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
