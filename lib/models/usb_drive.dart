/// A partition on a USB drive, as reported by `diskutil`.
class Partition {
  final String deviceId;
  final String content; // diskutil partition type, e.g. "Windows_FAT_32"
  final String? volumeName;
  final String? mountPoint;
  final int size;

  Partition({
    required this.deviceId,
    required this.content,
    required this.volumeName,
    required this.mountPoint,
    required this.size,
  });

  /// Filesystems a CDJ can read: FAT32 (both MBR partition types macOS and
  /// rekordbox use) and HFS+ / Mac OS Extended (Journaled).
  static const _cdjFilesystems = {
    'Windows_FAT_32', // FAT32 LBA (0x0C) — written by macOS diskutil
    'DOS_FAT_32', // FAT32 CHS (0x0B) — written by CDJs / rekordbox
    'Apple_HFS', // Mac OS Extended (Journaled)
  };

  bool get isCdjFilesystem => _cdjFilesystems.contains(content);

  factory Partition.fromMap(Map<String, dynamic> m) => Partition(
        deviceId: m['DeviceIdentifier'] as String? ?? '',
        content: m['Content'] as String? ?? '',
        volumeName: m['VolumeName'] as String?,
        mountPoint: (m['MountPoint'] as String?)?.trim().isNotEmpty == true
            ? m['MountPoint'] as String
            : null,
        size: (m['Size'] as num?)?.toInt() ?? 0,
      );

  String get filesystemLabel => friendlyFilesystem(content);
}

enum DriveStatus { ready, needsFormat }

/// A whole external/physical USB disk plus a computed "is this CDJ-ready" verdict.
///
/// CDJ-ready (FAT32-only definition) means:
///   * partition scheme is MBR (Master Boot Record / FDisk_partition_scheme)
///   * exactly one partition
///   * that partition is FAT32
class UsbDrive {
  final String deviceId; // "disk4"
  final String deviceNode; // "/dev/disk4"
  final String mediaName; // "SanDisk Cruzer Blade Media"
  final String busProtocol; // "USB"
  final bool internal;
  final int totalSize;
  final String partitionScheme; // whole-disk Content
  final List<Partition> partitions;

  late final DriveStatus status;
  late final List<String> issues;

  UsbDrive({
    required this.deviceId,
    required this.deviceNode,
    required this.mediaName,
    required this.busProtocol,
    required this.internal,
    required this.totalSize,
    required this.partitionScheme,
    required this.partitions,
  }) {
    issues = _computeIssues();
    status = issues.isEmpty ? DriveStatus.ready : DriveStatus.needsFormat;
  }

  List<String> _computeIssues() {
    final out = <String>[];
    if (partitionScheme != 'FDisk_partition_scheme') {
      out.add(
          'Partition scheme is ${friendlyScheme(partitionScheme)} — CDJs need MBR (Master Boot Record); the CDJ-3000 cannot read GUID.');
    }
    if (partitions.isEmpty) {
      out.add(
          'Drive has no partitions — it needs a single FAT32 or HFS+ partition.');
      return out;
    }
    if (partitions.length > 1) {
      out.add(
          'Drive has ${partitions.length} partitions — CDJs only read the first.');
    }
    final bad = partitions.where((p) => !p.isCdjFilesystem).toList();
    if (bad.isNotEmpty) {
      final names = bad.map((p) => p.filesystemLabel).toSet().join(', ');
      out.add(
          'Filesystem is $names — CDJs need FAT32 or HFS+ (Mac OS Extended).');
    }
    return out;
  }

  /// Filesystem of the first partition, for display when ready.
  String get filesystemLabel =>
      partitions.isEmpty ? 'unformatted' : partitions.first.filesystemLabel;

  /// Best volume name to show / reuse when reformatting.
  String? get volumeName {
    for (final p in partitions) {
      if (p.volumeName != null && p.volumeName!.trim().isNotEmpty) {
        return p.volumeName;
      }
    }
    return null;
  }

  /// Filesystem path to scan for tracks, if a partition is mounted.
  String? get mountPoint {
    for (final p in partitions) {
      if (p.mountPoint != null) return p.mountPoint;
    }
    return null;
  }

  String get sizeLabel => formatBytes(totalSize);

  factory UsbDrive.fromDiskutil(
    Map<String, dynamic> listEntry,
    Map<String, dynamic> info,
  ) {
    final parts = ((listEntry['Partitions'] as List?) ?? [])
        .map((p) => Partition.fromMap(p as Map<String, dynamic>))
        .toList();
    return UsbDrive(
      deviceId: listEntry['DeviceIdentifier'] as String? ?? '',
      deviceNode: info['DeviceNode'] as String? ??
          '/dev/${listEntry['DeviceIdentifier']}',
      mediaName: (info['MediaName'] as String?)?.trim().isNotEmpty == true
          ? info['MediaName'] as String
          : 'USB Drive',
      busProtocol: info['BusProtocol'] as String? ?? 'USB',
      internal: info['Internal'] as bool? ?? false,
      totalSize: (info['TotalSize'] as num?)?.toInt() ??
          (listEntry['Size'] as num?)?.toInt() ??
          0,
      partitionScheme: info['Content'] as String? ??
          listEntry['Content'] as String? ??
          '',
      partitions: parts,
    );
  }
}

String friendlyScheme(String content) {
  switch (content) {
    case 'FDisk_partition_scheme':
      return 'MBR';
    case 'GUID_partition_scheme':
      return 'GUID (GPT)';
    case '':
      return 'none';
    default:
      return content;
  }
}

String friendlyFilesystem(String content) {
  switch (content) {
    case 'Windows_FAT_32':
    case 'DOS_FAT_32':
      return 'FAT32';
    case 'Windows_FAT_16':
    case 'DOS_FAT_16':
      return 'FAT16';
    case 'Apple_HFS':
      return 'HFS+ (Mac OS Extended)';
    case 'Apple_APFS':
      return 'APFS';
    case 'Windows_NTFS':
      return 'NTFS or exFAT';
    case 'Microsoft Basic Data':
      return 'exFAT/NTFS';
    case 'EFI':
      return 'EFI';
    case '':
      return 'unformatted';
    default:
      return content;
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1000 && i < units.length - 1) {
    size /= 1000;
    i++;
  }
  final precision = size >= 100 || i == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[i]}';
}

/// Sanitize a user-supplied label into a valid FAT32 volume name:
/// uppercase, A–Z 0–9 plus a few safe symbols, max 11 chars.
String sanitizeFatLabel(String input) {
  final cleaned = input
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 _\-]'), '')
      .trim();
  final trimmed = cleaned.length > 11 ? cleaned.substring(0, 11) : cleaned;
  return trimmed.isEmpty ? 'CDJ' : trimmed;
}
