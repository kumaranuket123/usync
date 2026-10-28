import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../../data/repositories/legacy_content_sealer.dart';
import '../../../domain/repositories/i_encryption_repository.dart';

/// Keeps this phone's encryption keys in step with the server while the main screens are open:
/// once when they open and again each time the app comes back to the foreground. It shows nothing.
class EncryptionSyncGate extends StatefulWidget {
  const EncryptionSyncGate({super.key, required this.child});
  final Widget child;

  @override
  State<EncryptionSyncGate> createState() => _EncryptionSyncGateState();
}

class _EncryptionSyncGateState extends State<EncryptionSyncGate> with WidgetsBindingObserver {
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_lastSync) > const Duration(seconds: 20)) _sync();
  }

  Future<void> _sync() async {
    _lastSync = DateTime.now();
    if (!GetIt.I.isRegistered<IEncryptionRepository>()) return;
    await GetIt.I<IEncryptionRepository>().sync(); // never throws; the result is read where it is shown
    // With the keys in step, content written before encryption is sealed (only this person's own rows).
    if (GetIt.I.isRegistered<LegacyContentSealer>()) await GetIt.I<LegacyContentSealer>().runIfDue(); // never throws
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
