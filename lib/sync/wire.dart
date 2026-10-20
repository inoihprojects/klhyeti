import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The connection under both pairing and sync: one JSON object per line
/// over a TLS socket, with a cap on how much the other side may send in
/// total, so a stranger on the open port can't make this device hold on
/// to an endless stream.
///
/// Problems are thrown as [failure] makes them, so pairing reports its
/// own kind of error and sync its own.
class Wire {
  final SecureSocket _socket;
  final Exception Function(String message) failure;

  /// Bytes the other side may send over the whole connection. Sync raises
  /// it once the caller has proved who it is.
  int limit;
  int _seen = 0;
  late final StreamIterator<String> _lines;

  Wire(this._socket, {required this.limit, required this.failure}) {
    final Stream<List<int>> capped = _socket.map<List<int>>((chunk) {
      _seen += chunk.length;
      if (_seen > limit) throw failure('The other device sent too much.');
      return chunk;
    });
    _lines = StreamIterator<String>(
      utf8.decoder.bind(capped).transform(const LineSplitter()),
    );
  }

  void send(Map<String, Object?> message) {
    _socket.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  Future<Map<String, Object?>> read(Duration within) async {
    final bool more = await _lines.moveNext().timeout(within);
    if (!more) throw failure('The other device closed the connection.');
    final Object? decoded = jsonDecode(_lines.current);
    if (decoded is! Map) {
      throw failure('The other device sent something unexpected.');
    }
    return decoded.cast<String, Object?>();
  }

  /// A polite close, so the last message sent arrives first.
  Future<void> close() async {
    try {
      await _socket.flush();
      await _socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Dead already, or slow to say goodbye: dropped below either way.
    }
    await abandon();
  }

  Future<void> abandon() async {
    _socket.destroy();
    try {
      await _lines.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Nothing useful to do if the stream had already finished.
    }
  }
}

/// Compares two byte strings in time that doesn't depend on where they
/// differ, so a secret can't be guessed a byte at a time.
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
