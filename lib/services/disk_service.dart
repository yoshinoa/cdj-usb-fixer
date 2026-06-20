import 'dart:convert';
import 'dart:io';

import '../models/usb_drive.dart';

class DiskException implements Exception {
  final String message;
  DiskException(this.message);
  @override
  String toString() => message;
}

/// macOS implementation of disk inspection / formatting, backed by `diskutil`.
///
/// All commands go through `bash -c` so we can pipe diskutil's plist output
/// through `plutil -convert json`, giving us JSON that Dart parses natively.
class DiskService {
  Future<String> _run(String command) async {
    final result = await Process.run('bash', ['-c', command]);
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw DiskException(err.isEmpty ? 'Command failed: $command' : err);
    }
    return result.stdout.toString();
  }

  /// `-plist` must come immediately after the subcommand (e.g. `list`/`info`),
  /// not at the end, or diskutil treats it as a device name.
  Future<Map<String, dynamic>> _diskutilJson(String subcommand,
      [String rest = '']) async {
    final cmd =
        'set -o pipefail; diskutil $subcommand -plist $rest | plutil -convert json -o - -';
    final out = await _run(cmd.trim());
    return jsonDecode(out) as Map<String, dynamic>;
  }

  /// All external, physical (USB) whole disks currently attached.
  Future<List<UsbDrive>> listDrives() async {
    final listJson = await _diskutilJson('list', 'external physical');
    final entries = (listJson['AllDisksAndPartitions'] as List?) ?? [];

    final drives = <UsbDrive>[];
    for (final entry in entries) {
      final map = entry as Map<String, dynamic>;
      final id = map['DeviceIdentifier'] as String?;
      if (id == null) continue;
      final info = await _diskutilJson('info', '/dev/$id');
      // Defence in depth: never surface an internal disk.
      if (info['Internal'] as bool? ?? false) continue;
      drives.add(UsbDrive.fromDiskutil(map, info));
    }
    return drives;
  }

  /// Erase [drive] and reformat it as a single MBR / FAT32 partition.
  ///
  /// This is destructive. Before erasing, we re-verify the target is an
  /// external, whole, non-internal disk so we can never wipe the boot drive.
  Future<void> formatForCdj(UsbDrive drive, String rawLabel) async {
    final info = await _diskutilJson('info', drive.deviceNode);

    if (info['Internal'] as bool? ?? false) {
      throw DiskException('Refusing: ${drive.deviceNode} is an internal disk.');
    }
    if (!(info['WholeDisk'] as bool? ?? false)) {
      throw DiskException('Refusing: ${drive.deviceNode} is not a whole disk.');
    }
    final node = info['DeviceNode'] as String? ?? drive.deviceNode;
    if (!node.startsWith('/dev/disk')) {
      throw DiskException('Refusing: unexpected device node "$node".');
    }

    final label = sanitizeFatLabel(rawLabel);
    await _run('diskutil eraseDisk "MS-DOS FAT32" "$label" MBRFormat $node');
  }
}
