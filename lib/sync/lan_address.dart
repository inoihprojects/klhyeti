import 'dart:io';

/// The port a device listens on while its pairing screen is open. If it
/// is taken, any free port is used and shown on screen instead.
const int defaultSyncPort = 42835;

/// Whether [address] can only be a device on the local network (or this
/// device itself): the IPv4 ranges set aside for private use.
///
/// Klhyeti connects to, and accepts connections from, nothing else. That
/// is what keeps "local network only" true now that Android has had to
/// be asked for its one, all-or-nothing network permission.
bool isPrivateLanAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  if (b.length != 4) return false;
  if (b[0] == 10) return true;
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
  if (b[0] == 192 && b[1] == 168) return true;
  if (b[0] == 169 && b[1] == 254) return true; // link-local
  if (b[0] == 127) return true; // this device
  return false;
}

class LanEndpoint {
  final InternetAddress address;
  final int port;
  const LanEndpoint(this.address, this.port);
}

/// Reads "192.168.1.20" or "192.168.1.20:42835" as typed by the user.
/// Null for anything that isn't a private address written in numbers:
/// names are never looked up, so typing one sends nothing anywhere.
LanEndpoint? parseLanEndpoint(String text) {
  final trimmed = text.trim();
  var host = trimmed;
  var port = defaultSyncPort;
  final colon = trimmed.lastIndexOf(':');
  if (colon != -1) {
    host = trimmed.substring(0, colon);
    final parsed = int.tryParse(trimmed.substring(colon + 1));
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    port = parsed;
  }
  final address = InternetAddress.tryParse(host);
  if (address == null || !isPrivateLanAddress(address)) return null;
  return LanEndpoint(address, port);
}

/// This device's own addresses on the local network, for showing to the
/// user. Empty when there is none, or when the system won't say.
Future<List<String>> localLanAddresses() async {
  final found = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (isPrivateLanAddress(address)) found.add(address.address);
      }
    }
  } catch (_) {
    // Some systems refuse to list interfaces. The other device's address
    // can still be typed in here, so this is not worth failing over.
  }
  return found;
}
