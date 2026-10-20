# Architecture

## Goals

- Open source, lightweight, no backend server, no account/cloud dependency.
- Runs on Android, Windows, and Arch Linux (and derivatives) from a single codebase (Flutter).
- Devices sync directly with each other over the local network when possible.
  If that fails or isn't available, an exported/imported sync file (movable by
  LocalSend, Syncthing, USB, etc.) is the guaranteed fallback transport.
- No silent auto-merge of conflicting edits: when both devices changed the
  same event since the last sync, the user is shown both versions and picks
  which one wins.

## Data model

Every event has:

- `id` (UUID v4) — stable identity. Generated once, on the device where the
  event is created, and never regenerated. This is what lets both devices
  recognize "this is the same event" across syncs.
- `title`, `description`, `location`, `startAt`, `endAt`, `allDay`
- `updatedAt` (UTC timestamp) — bumped on every local edit.
- `deleted` (bool, tombstone) — deletions are soft: we mark `deleted = true`
  and bump `updatedAt` instead of removing the row, so a deletion can be
  synced to the other device instead of silently "un-deleting" on next sync.
  The tombstone keeps only the id, the flag and the bookkeeping fields:
  title, description, location and times are wiped, both when deleting
  locally and when a tombstone arrives from a peer.
- `originDeviceId` — which device last wrote this row. Informational.
- `rev` and `history` — a random id for this version, and the ids of the
  versions it was made on top of, newest first (the last 32). Every edit,
  deletion and settled conflict makes a new `rev` and pushes the old one
  onto `history`. This, not the clock, is how sync tells a newer copy
  from a conflicting one (`lib/models/revision.dart`). Events saved
  before revisions existed get a `rev` worked out from their id and
  `updatedAt`, so every device gives the same old version the same one.

Stored locally in SQLite (via `sqflite` / `sqflite_common_ffi`) in the app's
private data folder, not the user's Documents. Android uses the SQLite
built into the system; the Windows and Linux builds carry their own copy
(from the `sqlite3` package), so nothing needs to be installed.

## Sync protocol (transport-agnostic)

The sync logic never talks to a socket or a file directly — it works against
a `SyncPayload`, which is just:

```json
{
  "deviceId": "...",
  "deviceName": "...",
  "generatedAt": "...",
  "events": [ /* every event, tombstones included, with rev and history */ ]
}
```

Reconciling an incoming payload, event by event:

1. Not found locally -> insert it.
2. Same `rev`, or ours has theirs in its history -> ours is the same or
   newer; keep it.
3. Theirs has ours in its history -> theirs was made on top of ours;
   take it.
4. Neither, but the content agrees -> both made the same edit. Both
   devices settle on the lower of the two revs, with the other in its
   history, so they converge without asking.
5. Neither -> a real conflict: both were edited independently. Don't
   overwrite. Show the two devices' versions side by side and let the
   user pick: "Keep newest" gives every conflict to the device edited
   most recently, and a manual mode lets single events be flipped. The
   chosen version is saved as a new rev whose history holds *both*
   sides, so every device, whichever side it holds, takes it as newer.

Unsettled conflicts change nothing and are found again by the next sync.
None of this depends on the devices' clocks agreeing, and it holds for
any number of devices: an edit made on top of another device's version
is never mistaken for a conflict, however it travelled. (Before 0.3 a
per-peer "last synced" time decided this, which made false conflicts
between three devices and trusted the clocks.)

This same reconciliation function is reused by both transports below, so
adding the second transport later is wiring, not new sync logic.

### Transport 1: file export/import (fallback, built first)

- "Export" writes a `SyncPayload` JSON file to disk.
- The user moves that file to the other device by whatever means they like
  (LocalSend, Syncthing-watched folder, USB, email-to-self, etc.) — the app
  doesn't care.
- "Import" reads a chosen file and runs it through the reconciler above.

This is simple, has no networking code at all, and works even if the two
devices are never on the same network at the same time.

### Transport 2: direct local-network sync (primary, built after the fallback works)

Built in steps; pairing and transfer exist, discovery does not yet.

- **Addresses.** Only private IPv4 addresses are ever connected to or
  accepted from (`lib/sync/lan_address.dart`). Names are never looked up.
- **Encryption.** TLS from `dart:io`. Each device makes its own P-256 key
  and self-signed certificate on first use (`lib/sync/tls_identity.dart`).
  The certificate names nobody and carries no creation date. Pairing and
  transfer both talk through `lib/sync/wire.dart`: one JSON object per
  line, with a cap on how much the other side may send.
- **Pairing** (`lib/sync/pairing.dart`). Both devices open the pairing
  screen; each listens while it is open. One connects to the other's
  address. They exchange certificates and a random number each, the
  connecting device committing to its number before it sees the other's,
  and both show a six-character hexadecimal code derived from all four. If the users
  confirm the codes match, each device stores the other's certificate and
  a shared 32-byte secret. From then on a connection is trusted only if
  the listening device presents exactly that certificate and the
  connecting device sends that secret inside the encrypted connection.
- **Discovery** (to come): a small UDP announcement on the local network,
  so the address doesn't have to be typed. Not mDNS: the Dart package for
  it can only search, not announce.
- **Transfer** (`lib/sync/direct_sync.dart`). The other device connects,
  accepting only the certificate stored at pairing, and sends the shared
  secret. The listening device sends everything it has; the connecting
  device reconciles it exactly as it would a sync file (its user may
  settle conflicts there and then) and sends back everything it then
  has; the listening device takes each version made on top of its own
  (`acceptMerged`). Conflicts left unsettled stay conflicts on both, to
  be settled on either. A device busy with another sync answers "busy";
  the caller waits a random moment and tries again, so two devices that
  start at once don't keep refusing each other.
- **When** (`lib/sync/sync_service.dart`). While Klhyeti is open (on
  Android: in the foreground) and something is paired, it listens for
  paired devices. The sync button syncs with every paired device it can
  reach, at the address each was last seen at; each side records the
  other's address whenever they sync. Automatic sync (off by default)
  also syncs when the app opens and a few seconds after each change made
  on the device, and leaves any conflicts for the user rather than
  interrupting.
- The file transport stays as the fallback (captive networks, client
  isolation on the Wi-Fi router, devices on different subnets and
  firewalls all break direct connections — this is common enough that
  the fallback has to keep working, not just exist for day one).

## Why Flutter

Single Dart codebase compiles to genuinely native apps on Android, Windows,
and Linux (desktop support is stable, not experimental). Mature calendar
widgets, large community/beginner resources, and hot reload for fast
iteration. Binaries are heavier than a pure-native app but "lightweight" in
the sense that matters here: no bundled Chromium, no background services,
modest memory footprint, and a single toolchain to learn instead of three.

## Build order

1. Android app: local calendar backed by SQLite. Done.
2. File export/import sync, tested by hand between two installs. Done.
3. Windows and Linux desktop builds from the same codebase. Done.
4. Direct local-network sync on top of the same payload and reconciler.
   Pairing and transfer done; discovery next.
