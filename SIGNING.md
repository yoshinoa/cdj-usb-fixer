# Signing & notarizing CDJ USB for distribution

`scripts/make_dmg.sh` produces a signed, notarized, warning-free `.dmg` once the
prerequisites below are met. Account: `alex@jiye.ca` (team `6UZ49M64YB`).

This reuses the same Developer ID and notarytool profile as the `reel` project —
notarization credentials are account-level, so one profile works for any app.

## Prerequisites

1. **Paid Apple Developer Program** + a **Developer ID Application** certificate
   in your login keychain. Verify:

   ```
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

   You should see: `"Developer ID Application: Alexander Yoshino (6UZ49M64YB)"`

2. A **notarytool keychain profile** (named `reel-notary` here, already stored
   for the reel project). To recreate it:

   ```
   xcrun notarytool store-credentials reel-notary \
     --apple-id alex@jiye.ca --team-id 6UZ49M64YB \
     --password <app-specific-password>
   ```

## Build the DMG

```
./scripts/make_dmg.sh
```

Signing identity is auto-detected from the keychain; the notary profile comes
from `scripts/signing.env` (gitignored). Output: `dist/CDJ-USB-<version>.dmg`.

- Set nothing → unsigned DMG (right-click → Open to run).
- Identity only (comment out `CDJUSB_NOTARY_PROFILE`) → signed, not notarized.
- Identity + profile → signed + notarized + stapled (warning-free).

## Notes

- Entitlements come from `macos/Runner/Release.entitlements`. The **App Sandbox
  is intentionally disabled** — the app shells out to `diskutil` and reads
  `~/Library/Pioneer/rekordbox/master.db`, which a sandbox would block.
- The bundled **SQLCipher** frameworks are re-signed with your Developer ID, so
  hardened-runtime library validation passes — no need to disable it.
- First launch after notarization shows a normal "downloaded from the internet"
  prompt, not the "unidentified developer" block.
