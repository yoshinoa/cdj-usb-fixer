# CDJ USB

A macOS app that makes sure your USB stick — and the tracks on it — will
actually play on Pioneer CDJs before you're standing in the booth.

![Flutter](https://img.shields.io/badge/Flutter-macOS-blue)

## What it does

**Checks your USB stick.** Lists every external USB drive and verdicts it
against what a CDJ expects:

- Partition scheme is **MBR** (Master Boot Record) — the CDJ-3000 cannot read
  GUID/GPT, which is what macOS Disk Utility picks by default
- A **single partition** — CDJs only read the first one
- Filesystem is **FAT32** or **HFS+** — not exFAT, not APFS, not NTFS

**Formats for CDJ in one click.** Erases the stick to a single MBR/FAT32
partition (with a very loud confirmation first — this is destructive).

**Finds tracks CDJs refuse to play.** The headline case: WAV files written as
`WAVE_FORMAT_EXTENSIBLE` (0xFFFE). rekordbox plays them fine, so you find out
on the player. The app scans either a USB stick or your entire rekordbox
collection and flags every affected file.

**Fixes them losslessly.** For EXTENSIBLE files that are plain PCM underneath,
the fix rewrites only the WAV `fmt ` header in place — the audio bytes are
untouched, so it's bit-perfect. Files that are genuinely float-encoded are
flagged as needing re-encoding instead.

## rekordbox library scanning

The app reads track locations from the rekordbox 6/7 database
(`~/Library/Pioneer/rekordbox/master.db`). The live database is never opened —
it's copied to a temp directory, read read-only via SQLCipher, then deleted.

## Install

Grab the `.dmg` from [Releases](https://github.com/yoshinoa/cdj-usb-fixer/releases),
drag the app to Applications.

On first scan, macOS will ask for permission to access **removable volumes**
(and **Documents**/**Downloads** for library scans, if your tracks live there).
If you decline and regret it: System Settings → Privacy & Security →
Files & Folders → CDJ USB.

## Build from source

```
flutter pub get
flutter build macos
```

To produce a signed, notarized `.dmg`, see [SIGNING.md](SIGNING.md) — with no
signing identity configured, `./scripts/make_dmg.sh` still produces an unsigned
DMG (right-click → Open to run).

## How the pieces fit

| Component | Role |
|---|---|
| `lib/services/disk_service.dart` | Drive listing + formatting via `diskutil` (plist output piped through `plutil` to JSON) |
| `lib/services/track_service.dart` | Pure-Dart WAV header inspection and lossless in-place fixing |
| `lib/services/library_service.dart` | Decrypts a copy of rekordbox's `master.db` (SQLCipher) to enumerate track paths |
| `lib/models/usb_drive.dart` | The "is this stick CDJ-ready" verdict logic |

macOS only for now. The WAV scan/fix logic is pure Dart; the disk layer is the
platform-specific part.
