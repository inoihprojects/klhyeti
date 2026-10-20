import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/peer_repository.dart';
import '../data/settings_repository.dart';
import '../sync/lan_address.dart';
import '../sync/pairing.dart';
import '../sync/tls_identity.dart';
import '../theme/tokens.dart';

enum _Stage { preparing, waiting, connecting, comparing, finishing }

/// Pairs this device with another on the same local network.
///
/// Both devices open this screen. Each shows its own address and listens
/// for the other; the user types one device's address into the other,
/// compares the six-character code the two then show, and confirms on both.
/// The device listens only while this screen is open.
///
/// Pops with the paired device's name, or with nothing if the user left.
class PairScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final PeerRepository peers;

  const PairScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.peers,
  });

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final TextEditingController _addressField = TextEditingController();

  _Stage _stage = _Stage.preparing;
  String? _message;

  TlsIdentity? _identity;
  SecureServerSocket? _server;
  StreamSubscription<SecureSocket>? _incoming;
  List<String> _addresses = const [];
  PairingSession? _session;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _incoming?.cancel();
    _server?.close();
    _session?.cancel();
    _addressField.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final identity = await widget.peers.identity();
      final addresses = await localLanAddresses();
      final server = await _listen(identity);
      if (!mounted) {
        await server?.close();
        return;
      }
      setState(() {
        _identity = identity;
        _addresses = addresses;
        _server = server;
        // A connection that fails its TLS handshake arrives as an error
        // on this stream. It is somebody else's problem, not this
        // screen's, and listening carries on.
        _incoming = server?.listen(_onIncoming, onError: (Object _) {});
        _stage = _Stage.waiting;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.waiting;
        _message = 'Pairing could not start: $e';
      });
    }
  }

  /// Null when this device cannot listen at all; it can still connect.
  Future<SecureServerSocket?> _listen(TlsIdentity identity) async {
    for (final port in const [defaultSyncPort, 0]) {
      try {
        return await SecureServerSocket.bind(
          InternetAddress.anyIPv4,
          port,
          identity.serverContext(),
        );
      } on SocketException {
        // The usual port is taken: try any free one, which is then shown
        // beside the address.
      }
    }
    return null;
  }

  void _onIncoming(SecureSocket socket) {
    final identity = _identity;
    if (_stage != _Stage.waiting ||
        identity == null ||
        !isPrivateLanAddress(socket.remoteAddress)) {
      socket.destroy();
      return;
    }
    _begin(
      () => PairingSession.accept(
        socket,
        deviceId: widget.repo.deviceId,
        deviceName: widget.settings.deviceName,
        ownCert: identity.certDer,
      ),
    );
  }

  void _connect() {
    final identity = _identity;
    final endpoint = parseLanEndpoint(_addressField.text);
    if (identity == null) return;
    if (endpoint == null) {
      setState(() {
        _message = 'Type the address the other device shows, for example '
            '192.168.1.20.';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    _begin(() async {
      // Any certificate is accepted here, and only here: the two devices
      // have nothing to check it against yet. The code the users compare
      // next is what proves it is the right one, and from then on the
      // certificate seen now is the only one accepted.
      final socket = await SecureSocket.connect(
        endpoint.address,
        endpoint.port,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 8),
      );
      return PairingSession.connect(
        socket,
        deviceId: widget.repo.deviceId,
        deviceName: widget.settings.deviceName,
        ownCert: identity.certDer,
      );
    });
  }

  Future<void> _begin(Future<PairingSession> Function() open) async {
    setState(() {
      _stage = _Stage.connecting;
      _message = null;
    });
    try {
      final session = await open();
      if (!mounted) {
        await session.cancel();
        return;
      }
      setState(() {
        _session = session;
        _stage = _Stage.comparing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.waiting;
        _message = _describe(e);
      });
    }
  }

  String _describe(Object error) {
    if (error is PairingFailure) return error.message;
    if (error is TimeoutException) {
      return 'The other device did not answer in time.';
    }
    if (error is SocketException) {
      return 'Could not reach that address. Check that the other device '
          'has this screen open, that both are on the same network, and '
          'that no firewall is in the way.';
    }
    return 'Pairing failed: $error';
  }

  Future<void> _confirm() async {
    final session = _session;
    if (session == null) return;
    setState(() => _stage = _Stage.finishing);
    final device = await session.confirm();
    if (device != null) {
      await widget.peers.save(device);
    }
    if (!mounted) return;
    if (device == null) {
      setState(() {
        _session = null;
        _stage = _Stage.waiting;
        _message = 'The other device did not confirm, so nothing was paired.';
      });
      return;
    }
    Navigator.of(context).pop(device.name);
  }

  Future<void> _reject() async {
    final session = _session;
    setState(() {
      _session = null;
      _stage = _Stage.waiting;
      _message = 'Nothing was paired. If the two codes really were '
          'different, something on this network is interfering: try '
          'another network or a phone hotspot.';
    });
    await session?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final Widget body;
    if (_stage == _Stage.preparing) {
      body = const Center(child: Text('Preparing…'));
    } else if (session != null &&
        (_stage == _Stage.comparing || _stage == _Stage.finishing)) {
      body = _buildCompare(context, session);
    } else {
      body = _buildAddresses(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pair a device')),
      body: SafeArea(child: body),
    );
  }

  Widget _buildAddresses(BuildContext context) {
    final c = context.c;
    final server = _server;
    final bool connecting = _stage == _Stage.connecting;
    final message = _message;
    final String suffix =
        server == null || server.port == defaultSyncPort ? '' : ':${server.port}';

    final body = TextStyle(fontSize: 14, color: c.ink2, height: 1.45);
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: c.ink3,
    );

    return ListView(
      padding: const EdgeInsets.all(Insets.md),
      children: [
        Text(
          'Open this screen on both devices, on the same Wi-Fi or hotspot. '
          'Then type one device\'s address into the other.',
          style: body,
        ),
        const SizedBox(height: Insets.lg),
        Text('THIS DEVICE\'S ADDRESS', style: label),
        const SizedBox(height: Insets.sm),
        if (server == null)
          Text(
            'This device cannot accept a connection just now. Type the '
            'other device\'s address below instead.',
            style: body,
          )
        else if (_addresses.isEmpty)
          Text(
            'No local network address found. Check that Wi-Fi is on, or '
            'type the other device\'s address below instead.',
            style: body,
          )
        else
          for (final address in _addresses)
            SelectableText(
              '$address$suffix',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: c.ink,
                fontFeatures: tabularFigures,
              ),
            ),
        const SizedBox(height: Insets.lg),
        Text('THE OTHER DEVICE\'S ADDRESS', style: label),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _addressField,
          enabled: !connecting,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: const InputDecoration(hintText: '192.168.1.20'),
        ),
        const SizedBox(height: Insets.md),
        FilledButton(
          onPressed: connecting ? null : _connect,
          child: Text(connecting ? 'Connecting…' : 'Connect'),
        ),
        if (message != null) ...[
          const SizedBox(height: Insets.md),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.ink,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: Insets.lg),
        Text(
          'This device accepts a connection only while this screen is '
          'open, and only from an address on the local network.',
          style: TextStyle(fontSize: 13, color: c.ink3, height: 1.45),
        ),
      ],
    );
  }

  Widget _buildCompare(BuildContext context, PairingSession session) {
    final c = context.c;
    final bool finishing = _stage == _Stage.finishing;
    final String code = session.code;

    return Padding(
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            'Pairing with "${session.peerName}"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.ink2),
          ),
          const SizedBox(height: Insets.md),
          Text(
            code,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
              color: c.ink,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: Insets.md),
          Text(
            finishing
                ? 'Waiting for the other device to confirm…'
                : 'The other device should show the same six characters. '
                    'Confirm on both.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.ink2, height: 1.45),
          ),
          const Spacer(),
          FilledButton(
            onPressed: finishing ? null : _confirm,
            child: const Text('The codes match'),
          ),
          const SizedBox(height: Insets.sm),
          OutlinedButton(
            onPressed: _reject,
            child: Text(finishing ? 'Stop waiting' : 'They differ'),
          ),
        ],
      ),
    );
  }
}
