import 'dart:io';

import 'package:flutter/material.dart';

import 'models/usb_drive.dart';
import 'services/disk_service.dart';
import 'services/library_service.dart';
import 'services/track_service.dart';
import 'theme.dart';

void main() {
  runApp(const CdjUsbApp());
}

String friendlyFsError(Object e) {
  if (e is FileSystemException && e.osError?.errorCode == 1) {
    return 'macOS blocked access to ${e.path ?? 'the files'}.\n\n'
        'Open System Settings → Privacy & Security → Files & Folders → '
        'CDJ USB and allow Removable Volumes (and Documents/Downloads for '
        'library scans), then rescan.';
  }
  return e.toString();
}

class CdjUsbApp extends StatelessWidget {
  const CdjUsbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CDJ USB Checker',
      debugShowCheckedModeBanner: false,
      theme: rekordboxTheme(),
      home: const HomePage(),
    );
  }
}

// ───────────────────────────────────────── shared chrome

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('CDJ USB',
            style: Rb.ui(size: 14, weight: FontWeight.w700, spacing: 0.3)),
        const SizedBox(width: 9),
        Container(width: 1, height: 13, color: Rb.border),
        const SizedBox(width: 9),
        Text('FORMAT CHECKER', style: Rb.label(Rb.textFaint)),
      ],
    );
  }
}

class RbTopBar extends StatelessWidget {
  final Widget leading;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  const RbTopBar({
    super.key,
    required this.leading,
    this.actions = const [],
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Rb.panelHigh,
        border: Border(bottom: BorderSide(color: Rb.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (showBack) ...[
            _IconBtn(icon: Icons.chevron_left, onTap: onBack, size: 22),
            const SizedBox(width: 6),
          ],
          leading,
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  const _IconBtn(
      {required this.icon, this.onTap, this.size = 18, this.tooltip});

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final w = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hover && enabled ? Rb.rowHover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(widget.icon,
              size: widget.size,
              color: enabled
                  ? (_hover ? Rb.accent : Rb.textDim)
                  : Rb.textFaint),
        ),
      ),
    );
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: w)
        : w;
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: Rb.label(color)),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────── home

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _service = DiskService();
  final _library = LibraryService();
  List<UsbDrive> _drives = [];
  bool _loading = true;
  String? _error;
  String? _busyDeviceId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drives = await _service.listDrives();
      if (!mounted) return;
      setState(() {
        _drives = drives;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _format(UsbDrive drive) async {
    final label = await showDialog<String>(
      context: context,
      builder: (_) => FormatDialog(drive: drive),
    );
    if (label == null) return;

    setState(() => _busyDeviceId = drive.deviceId);
    try {
      await _service.formatForCdj(drive, label);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${drive.mediaName} is now CDJ-ready.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Rb.red,
          content: Text('Format failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
      await _refresh();
    }
  }

  void _scan(UsbDrive drive) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackScanPage(
        title: drive.volumeName ?? drive.mediaName,
        scanner: () => TrackService().scan(drive.mountPoint!),
      ),
    ));
  }

  void _scanLibrary() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackScanPage(
        title: 'rekordbox Library',
        scanner: () async =>
            TrackService().scanPaths(await _library.trackPaths()),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rb.bg,
      body: Column(
        children: [
          RbTopBar(
            leading: const Wordmark(),
            actions: [
              _IconBtn(
                icon: Icons.refresh,
                tooltip: 'Rescan devices',
                onTap: _loading ? null : _refresh,
              ),
            ],
          ),
          _LibrarySection(
            available: _library.available,
            onScan: _scanLibrary,
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _Loading(text: 'Scanning devices…');
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        color: Rb.red,
        title: 'Could not read disks',
        subtitle: _error!,
      );
    }
    if (_drives.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.usb_off,
        color: Rb.textFaint,
        title: 'No USB devices',
        subtitle: 'Connect a USB stick and rescan.',
      );
    }
    final colStyle = Rb.ui(size: 11.5, color: Rb.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // panel title bar
        Container(
          decoration: const BoxDecoration(
            color: Rb.panelHigh,
            border: Border(bottom: BorderSide(color: Rb.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text('Devices (${_drives.length})',
              style: Rb.ui(size: 13, weight: FontWeight.w600)),
        ),
        // column header
        Container(
          decoration: const BoxDecoration(
            color: Rb.header,
            border: Border(bottom: BorderSide(color: Rb.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const SizedBox(width: 27),
              Expanded(child: Text('Device', style: colStyle)),
              SizedBox(width: 120, child: Text('File System', style: colStyle)),
              SizedBox(width: 76, child: Text('Scheme', style: colStyle)),
              SizedBox(width: 132, child: Text('Status', style: colStyle)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _drives.length,
            itemBuilder: (_, i) => DriveCard(
              drive: _drives[i],
              busy: _busyDeviceId == _drives[i].deviceId,
              onFormat: () => _format(_drives[i]),
              onScan: _drives[i].mountPoint != null
                  ? () => _scan(_drives[i])
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class DriveCard extends StatefulWidget {
  final UsbDrive drive;
  final bool busy;
  final VoidCallback onFormat;
  final VoidCallback? onScan;

  const DriveCard({
    super.key,
    required this.drive,
    required this.busy,
    required this.onFormat,
    required this.onScan,
  });

  @override
  State<DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends State<DriveCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    final ready = drive.status == DriveStatus.ready;
    final statusColor = ready ? Rb.green : Rb.amber;
    final schemeBad = drive.partitionScheme != 'FDisk_partition_scheme';
    final fsBad = drive.partitions.isEmpty ||
        drive.partitions.any((p) => !p.isCdjFilesystem);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: _hover ? Rb.rowHover : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Rb.borderSoft)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SizedBox(
                      width: 27,
                      child: Icon(Icons.usb, size: 17, color: statusColor),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(drive.volumeName ?? drive.mediaName,
                            style: Rb.ui(size: 14, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${drive.sizeLabel}  ·  ${drive.deviceNode}  ·  ${drive.busProtocol}',
                          style: Rb.mono(size: 11, color: Rb.textDim),
                        ),
                        if (!ready) ...[
                          const SizedBox(height: 7),
                          ...drive.issues.map((issue) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                          Icons.warning_amber_rounded,
                                          size: 13,
                                          color: Rb.amber),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(issue,
                                          style: Rb.ui(
                                              size: 12.5,
                                              color: Rb.textDim)),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      drive.partitions.isEmpty ? '—' : drive.filesystemLabel,
                      style: Rb.mono(
                          size: 12, color: fsBad ? Rb.amber : Rb.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 76,
                    child: Text(
                      friendlyScheme(drive.partitionScheme),
                      style: Rb.mono(
                          size: 12,
                          color: schemeBad ? Rb.amber : Rb.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(
                        label: ready ? 'CDJ READY' : 'NEEDS FORMAT',
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // action strip
            Container(
              decoration: const BoxDecoration(
                color: Rb.panel,
                border: Border(top: BorderSide(color: Rb.borderSoft)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  if (widget.onScan != null)
                    OutlinedButton.icon(
                      onPressed: widget.busy ? null : widget.onScan,
                      icon: const Icon(Icons.travel_explore, size: 15),
                      label: const Text('SCAN TRACKS'),
                    ),
                  const Spacer(),
                  if (!ready)
                    FilledButton.icon(
                      onPressed: widget.busy ? null : widget.onFormat,
                      icon: widget.busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.bolt, size: 15),
                      label: Text(
                          widget.busy ? 'FORMATTING…' : 'FORMAT FOR CDJ'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibrarySection extends StatelessWidget {
  final bool available;
  final VoidCallback onScan;
  const _LibrarySection({required this.available, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Rb.panelHigh,
            border: Border(bottom: BorderSide(color: Rb.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text('Library', style: Rb.ui(size: 13, weight: FontWeight.w600)),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Rb.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 27,
                child: Icon(Icons.library_music,
                    size: 18, color: available ? Rb.accent : Rb.textFaint),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('rekordbox Collection',
                        style: Rb.ui(size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      available
                          ? 'Reads master.db on a copy to scan every WAV in your library.'
                          : 'rekordbox library not found on this Mac.',
                      style: Rb.mono(size: 11, color: Rb.textDim),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: available ? onScan : null,
                icon: const Icon(Icons.travel_explore, size: 15),
                label: const Text('SCAN LIBRARY'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────── track scan (browser)

class TrackScanPage extends StatefulWidget {
  final String title;
  final Future<List<TrackIssue>> Function() scanner;
  const TrackScanPage({super.key, required this.title, required this.scanner});

  @override
  State<TrackScanPage> createState() => _TrackScanPageState();
}

class _TrackScanPageState extends State<TrackScanPage> {
  final _service = TrackService();
  bool _scanning = true;
  bool _fixing = false;
  String? _error;
  List<TrackIssue> _issues = [];
  final Set<String> _fixed = {};
  final Map<String, String> _failed = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final issues = await widget.scanner();
      if (!mounted) return;
      setState(() {
        _issues = issues;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyFsError(e);
        _scanning = false;
      });
    }
  }

  Future<void> _fixAll() async {
    setState(() => _fixing = true);
    for (final issue in _issues) {
      if (!issue.fixable || _fixed.contains(issue.file.path)) continue;
      try {
        await _service.fix(issue);
        if (!mounted) return;
        setState(() => _fixed.add(issue.file.path));
      } catch (e) {
        if (!mounted) return;
        setState(() => _failed[issue.file.path] = friendlyFsError(e));
      }
    }
    if (mounted) setState(() => _fixing = false);
  }

  @override
  Widget build(BuildContext context) {
    final fixableLeft = _issues
        .where((i) => i.fixable && !_fixed.contains(i.file.path))
        .length;
    return Scaffold(
      backgroundColor: Rb.bg,
      body: Column(
        children: [
          RbTopBar(
            showBack: true,
            onBack: () => Navigator.of(context).pop(),
            leading: Row(
              children: [
                const Icon(Icons.travel_explore,
                    size: 18, color: Rb.accent),
                const SizedBox(width: 9),
                Text('TRACK SCAN', style: Rb.label(Rb.textDim)),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: Rb.border),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: Rb.ui(size: 14, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
          if (!_scanning && _issues.isNotEmpty)
            _FooterBar(
              fixableLeft: fixableLeft,
              fixing: _fixing,
              total: _issues.length,
              fixed: _fixed.length,
              onFixAll: fixableLeft > 0 && !_fixing ? _fixAll : null,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_scanning) {
      return const _Loading(text: 'Reading WAV headers…');
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        color: Rb.red,
        title: 'Scan failed',
        subtitle: _error!,
      );
    }
    if (_issues.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.verified,
        color: Rb.green,
        title: 'All tracks are CDJ-compatible',
        subtitle: 'No WAVE_FORMAT_EXTENSIBLE headers found.',
      );
    }
    return Column(
      children: [
        // notification strip
        Container(
          width: double.infinity,
          color: Rb.amber.withValues(alpha: 0.10),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Rb.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_issues.length} track(s) use the CDJ-incompatible EXTENSIBLE header. '
                  'Fixing rewrites the header in place — lossless, audio untouched.',
                  style: Rb.ui(size: 13, color: Rb.text),
                ),
              ),
            ],
          ),
        ),
        // column header
        Container(
          decoration: const BoxDecoration(
            color: Rb.header,
            border: Border(
                bottom: BorderSide(color: Rb.border),
                top: BorderSide(color: Rb.border)),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                  width: 34,
                  child: Text('#', style: Rb.ui(size: 11.5, color: Rb.textDim))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Track Title',
                      style: Rb.ui(size: 11.5, color: Rb.textDim))),
              SizedBox(
                  width: 150,
                  child: Text('Format',
                      style: Rb.ui(size: 11.5, color: Rb.textDim))),
              SizedBox(
                  width: 130,
                  child: Text('Status',
                      style: Rb.ui(size: 11.5, color: Rb.textDim))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _issues.length,
            itemBuilder: (_, i) {
              final issue = _issues[i];
              return _TrackRow(
                issue: issue,
                index: i + 1,
                fixed: _fixed.contains(issue.file.path),
                failed: _failed[issue.file.path],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrackRow extends StatefulWidget {
  final TrackIssue issue;
  final int index;
  final bool fixed;
  final String? failed;
  const _TrackRow({
    required this.issue,
    required this.index,
    required this.fixed,
    required this.failed,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final Color statusColor = widget.fixed
        ? Rb.green
        : widget.failed != null
            ? Rb.red
            : Rb.amber;
    final IconData statusIcon = widget.fixed
        ? Icons.check_circle
        : widget.failed != null
            ? Icons.error
            : Icons.warning_amber_rounded;
    final String statusText = widget.fixed
        ? 'FIXED'
        : widget.failed != null
            ? 'FAILED'
            : 'EXTENSIBLE';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: _hover ? Rb.rowHover : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: Rb.borderSoft, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('${widget.index}',
                  style: Rb.mono(size: 11.5, color: Rb.textFaint)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                issue.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Rb.ui(
                    size: 13, color: widget.fixed ? Rb.textDim : Rb.text),
              ),
            ),
            SizedBox(
              width: 150,
              child: Text('WAV · ${issue.rateLabel}',
                  style: Rb.mono(size: 11.5, color: Rb.textDim)),
            ),
            SizedBox(
              width: 130,
              child: Row(
                children: [
                  Icon(statusIcon, size: 13, color: statusColor),
                  const SizedBox(width: 7),
                  Text(statusText, style: Rb.label(statusColor, size: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterBar extends StatelessWidget {
  final int fixableLeft;
  final int total;
  final int fixed;
  final bool fixing;
  final VoidCallback? onFixAll;
  const _FooterBar({
    required this.fixableLeft,
    required this.total,
    required this.fixed,
    required this.fixing,
    required this.onFixAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Rb.panelHigh,
        border: Border(top: BorderSide(color: Rb.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Text('$total flagged', style: Rb.ui(size: 12, color: Rb.textDim)),
          if (fixed > 0) ...[
            Text('  ·  ', style: Rb.ui(size: 12, color: Rb.textFaint)),
            Text('$fixed fixed', style: Rb.ui(size: 12, color: Rb.green)),
          ],
          const Spacer(),
          FilledButton.icon(
            onPressed: onFixAll,
            icon: fixing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF06222E)),
                  )
                : const Icon(Icons.auto_fix_high, size: 15),
            label: Text(fixing
                ? 'FIXING…'
                : fixableLeft > 0
                    ? 'FIX ALL ($fixableLeft)'
                    : 'ALL FIXED'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────── format dialog

class FormatDialog extends StatefulWidget {
  final UsbDrive drive;
  const FormatDialog({super.key, required this.drive});

  @override
  State<FormatDialog> createState() => _FormatDialogState();
}

class _FormatDialogState extends State<FormatDialog> {
  late final TextEditingController _controller = TextEditingController(
      text: sanitizeFatLabel(widget.drive.volumeName ?? 'CDJ'));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Rb.panelHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Rb.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.bolt, size: 18, color: Rb.accent),
                  const SizedBox(width: 9),
                  Text('FORMAT FOR CDJ', style: Rb.label(Rb.text)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Rb.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Rb.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.delete_forever,
                        size: 18, color: Rb.red),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'This erases EVERYTHING on '
                        '"${widget.drive.volumeName ?? widget.drive.mediaName}" '
                        '(${widget.drive.sizeLabel}, ${widget.drive.deviceNode}). '
                        'Cannot be undone.',
                        style: Rb.ui(size: 13, color: Rb.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('VOLUME NAME', style: Rb.label(Rb.textDim)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                maxLength: 11,
                textCapitalization: TextCapitalization.characters,
                style: Rb.mono(size: 14, color: Rb.text),
                decoration: InputDecoration(
                  isDense: true,
                  counterStyle: Rb.mono(size: 10, color: Rb.textFaint),
                  helperText: 'FAT32 · uppercase · ≤ 11 chars',
                  helperStyle: Rb.ui(size: 11, color: Rb.textFaint),
                  filled: true,
                  fillColor: Rb.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Rb.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Rb.accent),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Rb.red,
                      foregroundColor: Colors.white,
                      textStyle: Rb.label(Colors.white),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                    ),
                    icon: const Icon(Icons.delete_forever, size: 15),
                    onPressed: () => Navigator.pop(
                        context, sanitizeFatLabel(_controller.text)),
                    label: const Text('ERASE & FORMAT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────── states

class _Loading extends StatelessWidget {
  final String text;
  const _Loading({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Rb.accent),
          ),
          const SizedBox(height: 18),
          Text(text, style: Rb.ui(size: 13, color: Rb.textDim, spacing: 0.5)),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _CenteredMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 18),
            Text(title, style: Rb.ui(size: 17, weight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Rb.ui(size: 13, color: Rb.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
