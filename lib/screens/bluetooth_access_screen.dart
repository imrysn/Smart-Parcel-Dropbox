import 'package:flutter/material.dart';

import '../services/biometric_service.dart';
import '../services/ble_dropbox_service.dart';
import '../services/ble_protocol.dart';
import '../services/service_locator.dart';
import '../widgets/user_ui.dart';

class BleWifiSetupScreen extends StatefulWidget {
  const BleWifiSetupScreen({super.key, required this.code});

  final BleSetupCode code;

  @override
  State<BleWifiSetupScreen> createState() => _BleWifiSetupScreenState();
}

class _BleWifiSetupScreenState extends State<BleWifiSetupScreen> {
  final _network = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _network.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<BleDropboxService>()
          .configureWifi(widget.code, _network.text, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on BleDropboxException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bluetooth Wi-Fi setup')),
        body: ListView(
          padding:
              UserUi.listPadding(context, top: 20, bottom: 32, maxWidth: 520),
          children: [
            const Text(
                'Stay near the Dropbox with its Bluetooth Wi-Fi screen open.'),
            const SizedBox(height: 16),
            TextField(
              controller: _network,
              enabled: !_busy,
              autocorrect: false,
              decoration:
                  const InputDecoration(labelText: 'Wi-Fi network name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'Wi-Fi password',
                  helperText: 'Leave blank for an open network'),
            ),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Connecting…' : 'Connect Dropbox')),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      );
}

class OfflineUnlockScreen extends StatefulWidget {
  const OfflineUnlockScreen({super.key, this.ownerDeviceId});

  final String? ownerDeviceId;

  @override
  State<OfflineUnlockScreen> createState() => _OfflineUnlockScreenState();
}

class _OfflineUnlockScreenState extends State<OfflineUnlockScreen> {
  final _service = getIt<BleDropboxService>();
  OfflineUnlockGrant? _grant;
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _run(() async {
      final grant = await _service.readGrant();
      if (widget.ownerDeviceId == null ||
          grant?.deviceId == widget.ownerDeviceId?.toUpperCase()) {
        _grant = grant;
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BleDropboxException catch (error) {
      _message = error.message;
    } catch (_) {
      _message =
          'Could not complete offline access. Check the connection and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grant = _grant;
    final valid = grant != null && grant.expiry.isAfter(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Offline unlock')),
      body: ListView(
        padding:
            UserUi.listPadding(context, top: 20, bottom: 32, maxWidth: 520),
        children: [
          const Text(
              'The primary owner can prepare access for up to 8 hours while the Dropbox is online.'),
          if (valid) ...[
            const SizedBox(height: 16),
            Text(
                'Access expires ${MaterialLocalizations.of(context).formatCompactDate(grant.expiry)} at '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(grant.expiry))}.'),
            const SizedBox(height: 12),
            const Text(
                'When the Dropbox is offline, wake it, hold the blue button for two seconds, '
                'then press red on Offline Settings. Stay near the box.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final approved = await getIt<BiometricService>()
                            .authenticate(
                                reason: 'Unlock the received-parcel door');
                        if (!approved || !mounted) return;
                        await _service.unlockReceivedDoor(grant);
                        _message =
                            'Received-parcel door unlocked. It relocks automatically.';
                      }),
              child: const Text('Unlock received-parcel door'),
            ),
          ] else if (!_busy) ...[
            const SizedBox(height: 12),
            Text(grant == null
                ? 'No offline access is saved on this phone.'
                : 'Offline access has expired.'),
          ],
          if (widget.ownerDeviceId != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        _grant =
                            await _service.prepareGrant(widget.ownerDeviceId!);
                        _message = 'Offline access is ready on this phone.';
                      }),
              child: Text(
                  valid ? 'Renew offline access' : 'Prepare offline access'),
            ),
          ],
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator()),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!)
          ],
        ],
      ),
    );
  }
}
