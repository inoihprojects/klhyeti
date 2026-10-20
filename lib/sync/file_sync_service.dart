import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../data/event_repository.dart';
import 'sync_payload.dart';
import 'sync_reconciler.dart';

/// Phase-1 sync transport (see ARCHITECTURE.md): writes/reads a JSON
/// [SyncPayload] file. Moving that file between devices is left to the user
/// — LocalSend, Syncthing, USB, whatever's on hand. This is also the
/// permanent fallback once direct local-network sync exists, for whenever
/// discovery doesn't work (different subnets, client isolation, etc).
class FileSyncService {
  final EventRepository repo;
  const FileSyncService(this.repo);

  /// Returns the saved file's path, or null if the user cancelled the save
  /// dialog. [deviceName] travels in the file so the other device can say
  /// whose version is whose.
  Future<String?> exportToFile({String? deviceName}) async {
    final events = await repo.allEventsForExport();
    final payload = SyncPayload(
      deviceId: repo.deviceId,
      deviceName: deviceName,
      generatedAt: DateTime.now().toUtc(),
      events: events,
    );
    final content = payload.encode();
    final bytes = Uint8List.fromList(utf8.encode(content));
    final defaultName =
        'klhyeti-sync-${DateTime.now().toUtc().millisecondsSinceEpoch}.json';

    // On Android, scoped storage means we can't just write to an arbitrary
    // path — file_picker needs the bytes to write the file itself via the
    // save dialog. On desktop it only returns the chosen path and we write
    // the file ourselves.
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save klhyeti sync file',
      fileName: defaultName,
      bytes: Platform.isAndroid ? bytes : null,
    );

    if (savePath == null) return null;

    if (!Platform.isAndroid) {
      await File(savePath).writeAsBytes(bytes);
    }

    return savePath;
  }

  /// Returns null if the user cancelled the file picker.
  Future<ReconcileResult?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a klhyeti sync file',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final String content;
    final pickedBytes = picked.bytes;
    final pickedPath = picked.path;
    if (pickedBytes != null) {
      content = utf8.decode(pickedBytes);
    } else if (pickedPath != null) {
      content = await File(pickedPath).readAsString();
    } else {
      throw StateError('Picked file exposed neither bytes nor a path.');
    }

    final payload = SyncPayload.decode(content);
    return reconcile(repo, payload);
  }
}
