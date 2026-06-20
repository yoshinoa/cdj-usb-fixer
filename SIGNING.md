# Signing & notarizing CDJ USB for distribution

`scripts/make_dmg.sh` produces a signed, notarized, warning-free `.dmg` once the
prerequisites below are met.

## Prerequisites

1. **Paid Apple Developer Program** + a **Developer ID Application** certificate
   in your login keychain. Verify:

   ```
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

   You should see a line like:
   `"Developer ID Application: <Your Name> (<TEAMID>)"`

2. A **notarytool keychain profile**. Create one once with an app-specific
   password (https://account.apple.com → Sign-In & Security → App-Specific
   Passwords):

   ```
   xcrun notarytool store-credentials <profile-name> \
     --apple-id <your-apple-id> --team-id <TEAMID> \
     --password <app-specific-password>
   ```

   Then point the build at it in `scripts/signing.env` (gitignored):

   ```
   CDJUSB_NOTARY_PROFILE="<profile-name>"
   ```

## Build the DMG

```
./scripts/make_dmg.sh
```

The signing identity is auto-detected from your keychain; the notary profile is
read from `scripts/signing.env` (gitignored). Output: `dist/CDJ-USB-<version>.dmg`.

- Set nothing → unsigned DMG (right-click → Open to run).
- Identity only (no `CDJUSB_NOTARY_PROFILE`) → signed, not notarized.
- Identity + profile → signed + notarized + stapled (warning-free).

## Notes

- Entitlements come from `macos/Runner/Release.entitlements`. The **App Sandbox
  is intentionally disabled** — the app shells out to `diskutil` and reads
  `~/Library/Pioneer/rekordbox/master.db`, which a sandbox would block.
- The bundled **SQLCipher** frameworks are re-signed with your Developer ID, so
  hardened-runtime library validation passes — no need to disable it.
- First launch after notarization shows a normal "downloaded from the internet"
  prompt, not the "unidentified developer" block.
