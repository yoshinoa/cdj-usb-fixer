import 'dart:ffi';
import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

class LibraryException implements Exception {
  final String message;
  const LibraryException(this.message);
  @override
  String toString() => message;
}

/// Reads track locations from the rekordbox 6/7 library (`master.db`).
///
/// The database is SQLCipher-encrypted with a key shared by every rekordbox
/// install. We never open the live file — it's copied to a temp dir first,
/// read read-only, then deleted.
class LibraryService {
  static const _key =
      '402fd482c38817c35ffa8ffb8c7d93143b749e7d315df7a81732a1ff43608497';

  static bool _cipherReady = false;

  static void _ensureCipher() {
    if (_cipherReady) return;
    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    } else if (Platform.isMacOS) {
      // SQLCipher is linked into the app bundle; resolve from the process.
      open.overrideFor(OperatingSystem.macOS, DynamicLibrary.process);
    } else if (Platform.isIOS) {
      open.overrideFor(OperatingSystem.iOS, DynamicLibrary.process);
    }
    _cipherReady = true;
  }

  String? get masterDbPath {
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final p = '$home/Library/Pioneer/rekordbox/master.db';
    return File(p).existsSync() ? p : null;
  }

  bool get available => masterDbPath != null;

  /// Copy master.db (+ any WAL/SHM) to a temp dir, decrypt, and return every
  /// non-deleted track's absolute path. The live database is never touched.
  Future<List<String>> trackPaths() async {
    final src = masterDbPath;
    if (src == null) {
      throw const LibraryException(
          'rekordbox library not found (~/Library/Pioneer/rekordbox/master.db).');
    }
    _ensureCipher();

    final tmpDir = await Directory.systemTemp.createTemp('cdj_rb_');
    final copyPath = '${tmpDir.path}/master.db';
    try {
      await File(src).copy(copyPath);
      for (final ext in const ['-wal', '-shm']) {
        final s = File('$src$ext');
        if (await s.exists()) await s.copy('$copyPath$ext');
      }

      final db = sqlite3.open(copyPath);
      try {
        // Fail loudly if the system's plain SQLite slipped in.
        final ver = db.select('PRAGMA cipher_version');
        if (ver.isEmpty ||
            (ver.first.values.first?.toString().trim().isEmpty ?? true)) {
          throw const LibraryException(
              'SQLCipher is not active — cannot read the encrypted library.');
        }
        // The key is a passphrase (SQLCipher runs its KDF over the hex string),
        // NOT a raw x'...' blob — the blob form silently fails to decrypt.
        db.execute("PRAGMA key = '$_key'");
        db.execute('PRAGMA cipher_compatibility = 4');

        final rows = db.select(
          'SELECT FolderPath FROM djmdContent '
          'WHERE FolderPath IS NOT NULL AND rb_local_deleted = 0',
        );
        return [
          for (final row in rows)
            if ((row['FolderPath'] as String?)?.isNotEmpty ?? false)
              row['FolderPath'] as String,
        ];
      } finally {
        db.dispose();
      }
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
