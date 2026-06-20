import 'dart:io';
import 'dart:typed_data';

/// Why a track won't play on a CDJ, and whether we can fix it losslessly.
class TrackIssue {
  final File file;
  final String name; // basename
  final int sampleRate;
  final int bitDepth;
  final String reason;
  final bool fixable;

  TrackIssue({
    required this.file,
    required this.name,
    required this.sampleRate,
    required this.bitDepth,
    required this.reason,
    required this.fixable,
  });

  String get rateLabel =>
      '${(sampleRate / 1000).toStringAsFixed(sampleRate % 1000 == 0 ? 0 : 1)}k/${bitDepth}bit';
}

/// Parsed essentials from a WAV `fmt ` chunk.
class _WavFmt {
  final int formatTag; // 0x0001 PCM, 0x0003 float, 0xFFFE extensible
  final int subFormat; // first 2 bytes of extensible SubFormat GUID
  final int channels;
  final int sampleRate;
  final int bitDepth;
  _WavFmt(this.formatTag, this.subFormat, this.channels, this.sampleRate,
      this.bitDepth);
}

const _wavExts = {'.wav', '.wave'};

class TrackService {
  /// Walk [mountPoint] and return every track a CDJ would refuse.
  ///
  /// The headline case: WAVs written as WAVE_FORMAT_EXTENSIBLE (0xFFFE). CDJs
  /// read the "extensible/multichannel" flag and refuse the file even though
  /// it's plain stereo PCM. rekordbox tolerates it, the player does not.
  Future<List<TrackIssue>> scan(String mountPoint) async {
    final dir = Directory(mountPoint);
    if (!await dir.exists()) return [];

    final issues = <TrackIssue>[];
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final issue = await inspectWav(entity);
      if (issue != null) issues.add(issue);
    }
    _sort(issues);
    return issues;
  }

  /// Inspect an explicit list of paths (e.g. from the rekordbox library).
  /// Missing files are skipped silently.
  Future<List<TrackIssue>> scanPaths(Iterable<String> paths) async {
    final issues = <TrackIssue>[];
    for (final p in paths) {
      final file = File(p);
      if (!await file.exists()) continue;
      final issue = await inspectWav(file);
      if (issue != null) issues.add(issue);
    }
    _sort(issues);
    return issues;
  }

  /// Classify one file: returns an issue if it's a CDJ-incompatible WAV.
  Future<TrackIssue?> inspectWav(File file) async {
    final name = file.uri.pathSegments.last;
    if (name.startsWith('._')) return null; // macOS AppleDouble sidecar
    final dot = name.lastIndexOf('.');
    if (dot < 0 || !_wavExts.contains(name.substring(dot).toLowerCase())) {
      return null;
    }
    final fmt = await _readFmt(file);
    if (fmt == null || fmt.formatTag != 0xFFFE) return null;
    final pcm = fmt.subFormat == 0x0001;
    return TrackIssue(
      file: file,
      name: name,
      sampleRate: fmt.sampleRate,
      bitDepth: fmt.bitDepth,
      reason: pcm
          ? 'WAV header is WAVE_FORMAT_EXTENSIBLE — CDJ refuses it.'
          : 'WAV header is EXTENSIBLE float — needs re-encoding to PCM.',
      fixable: pcm,
    );
  }

  void _sort(List<TrackIssue> issues) => issues
      .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<_WavFmt?> _readFmt(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(8192);
      if (head.length < 16) return null;
      final bd = ByteData.sublistView(head);
      if (_tag(head, 0) != 'RIFF' || _tag(head, 8) != 'WAVE') return null;
      var i = 12;
      while (i + 8 <= head.length) {
        final cid = _tag(head, i);
        final size = bd.getUint32(i + 4, Endian.little);
        if (cid == 'fmt ' && i + 8 + 16 <= head.length) {
          final tag = bd.getUint16(i + 8, Endian.little);
          final ch = bd.getUint16(i + 10, Endian.little);
          final sr = bd.getUint32(i + 12, Endian.little);
          final depth = bd.getUint16(i + 22, Endian.little);
          var sub = 0;
          if (tag == 0xFFFE && i + 8 + 26 <= head.length) {
            sub = bd.getUint16(i + 8 + 24, Endian.little);
          }
          return _WavFmt(tag, sub, ch, sr, depth);
        }
        i += 8 + size + (size & 1);
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  /// Losslessly rewrite an EXTENSIBLE/PCM WAV's `fmt ` chunk to standard PCM
  /// (0x0001). The audio sample bytes are copied untouched, so this is
  /// bit-perfect. Written to a temp file then atomically renamed over the
  /// original.
  Future<void> fix(TrackIssue issue) async {
    if (!issue.fixable) {
      throw const FormatException('This file needs re-encoding, not a header fix.');
    }
    final data = await issue.file.readAsBytes();
    final bd = ByteData.sublistView(data);
    if (_tag(data, 0) != 'RIFF' || _tag(data, 8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file.');
    }

    final out = BytesBuilder();
    out.add(data.sublist(0, 12)); // RIFF + (size placeholder) + WAVE

    var i = 12;
    var fixedAny = false;
    while (i + 8 <= data.length) {
      final cid = _tag(data, i);
      final size = bd.getUint32(i + 4, Endian.little);
      final pad = size & 1;
      final end = (i + 8 + size + pad).clamp(0, data.length);

      if (cid == 'fmt ' && bd.getUint16(i + 8, Endian.little) == 0xFFFE) {
        // New 16-byte PCM fmt: tag=0x0001 + the standard 14 bytes that follow.
        out.add(const [0x66, 0x6d, 0x74, 0x20]); // "fmt "
        final lenBytes = ByteData(4)..setUint32(0, 16, Endian.little);
        out.add(lenBytes.buffer.asUint8List());
        out.add(const [0x01, 0x00]);
        out.add(data.sublist(i + 8 + 2, i + 8 + 16));
        fixedAny = true;
      } else if (cid == 'fact') {
        // Optional, redundant for PCM — drop it.
      } else {
        out.add(data.sublist(i, end));
      }
      i += 8 + size + pad;
    }

    if (!fixedAny) {
      throw const FormatException('No EXTENSIBLE fmt chunk found.');
    }

    final bytes = out.toBytes();
    ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);

    final tmp = File('${issue.file.path}.cdjfix.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(issue.file.path);
  }

  String _tag(List<int> b, int off) =>
      String.fromCharCodes(b.sublist(off, off + 4));
}
