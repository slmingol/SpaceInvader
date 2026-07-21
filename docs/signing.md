# Code Signing & Notarization

This document covers how SpaceInvader is signed, notarized, and distributed outside the Mac App Store. It documents the exact steps used to set this up, including points of confusion and how they were resolved.

---

## Step 0 — Enroll in the Apple Developer Program (one-time)

This only needs to be done once per Apple ID.

1. Go to **developer.apple.com/programs/enroll**
2. Sign in with your Apple ID (create one at appleid.apple.com if needed)
3. Choose entity type:
   - **Individual** — simplest, $99/year, your legal name appears on certificates and in Gatekeeper dialogs
   - **Organization** — requires a D-U-N-S number, used when publishing under a company name
4. Agree to the Apple Developer Program License Agreement
5. Pay the $99/year fee (credit card or PayPal)
6. Wait for the confirmation email — Individual enrollments typically complete within minutes

Once enrolled, your Apple ID gains access to App Store Connect, developer certificates, and the notary service.

> If you can already sign into App Store Connect (appstoreconnect.apple.com), you are already enrolled.

---

## Step 1 — Add your Apple ID to Xcode

1. Xcode → Settings (Cmd+,) → **Apple Accounts** tab
2. Click **+** → **Apple ID** → sign in
3. Click **Download Manual Profiles** to sync certificates

---

## Step 2 — Create a Developer ID Application certificate

This certificate is used to sign apps for distribution outside the App Store. It is different from the Apple Development certificate used for local builds.

1. In Xcode Settings → Apple Accounts, click your team row (the chevron on the right)
2. Click **Manage Certificates...**
3. Click **+** → **Developer ID Application**
4. Xcode generates the certificate and stores it in your login keychain

**Common point of confusion:** After creating the certificate, the Signing Certificate dropdown in Xcode's Signing & Capabilities tab still shows "Development". This is expected and correct. When `Automatically manage signing` is enabled, Xcode uses the Development certificate for local builds and automatically switches to Developer ID Application when you Archive for distribution. Do not try to change this dropdown for day-to-day development.

---

## Step 3 — Archive and notarize locally (manual, one-off)

To produce a signed, notarized build from Xcode manually:

1. In Xcode, confirm the run destination is **My Mac** (not a simulator) — visible in the center top bar
2. **Product → Archive** (from the macOS menu bar, not inside the Xcode window)
3. Organizer opens automatically (Window → Organizer if it doesn't)
4. Click **Distribute App**
5. Choose **Direct Distribution** (not App Store Connect — that submits to the App Store)
6. Click **Distribute** — Xcode signs and submits to Apple's notary service automatically
7. Status shows "In Progress" in the Submission Status panel — typically takes 5–30 minutes
8. When status shows **Ready to distribute**, click **Export Notarized App**

**About notarization time:** Notarization is fully automated on Apple's end — no human review. It runs Apple's malware scanning pipeline. Duration depends on Apple server load and is not controllable. You can close Xcode Organizer while waiting. Enable Xcode notifications (System Settings → Notifications → Xcode) to be alerted when it completes.

**Accessibility permission after rebuild:** macOS ties Accessibility permission to the app's code signature. Rebuilding with a different certificate (e.g. switching from ad-hoc to Developer ID) revokes the permission for the new binary. Fix: System Settings → Privacy & Security → Accessibility → toggle SpaceInvader off and back on.

---

## CI/CD setup (GitHub Actions)

The release workflow (`.github/workflows/release.yml`) handles signing and notarization on every `v*` tag push.

### Secrets required

Add these under the GitHub repo → Settings → Secrets and variables → Actions:

| Secret | Description |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate exported from Keychain |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` |
| `APPLE_ID` | Apple ID email address |
| `APPLE_ID_PASSWORD` | App-specific password (not the Apple ID password — see below) |
| `APPLE_TEAM_ID` | 10-character team ID (e.g. `U59C467KN7`) |

**Finding your Team ID:** It appears in Xcode under the target's Signing & Capabilities → Team, and in Keychain Access in the certificate name: `Developer ID Application: Your Name (TEAMID)`.

### Exporting the certificate as .p12

1. Open **Keychain Access** → select the **login** keychain → **My Certificates** tab
2. Look for **Developer ID Application: Your Name (TEAMID)** — it will have a disclosure triangle showing the private key underneath
3. Right-click the certificate row (not the key row) → **Export**
4. Save as `.p12` format with a strong password

**Common point of confusion:** The certificate only appears if you selected the **login** keychain on the left. The **Local Items** keychain and other keychains may not show it. Also, the export option is on the certificate row, not the private key row.

### Base64-encoding and setting the secret

```bash
base64 -i ~/Certificates.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12 -R your-org/SpaceInvader
```

Or copy to clipboard and paste manually:
```bash
base64 -i ~/Certificates.p12 | pbcopy
```

### App-specific password

The `APPLE_ID_PASSWORD` secret must be an app-specific password, not your Apple ID login password. Apple requires this for automated CLI tools like `xcrun notarytool`.

1. Go to **appleid.apple.com** → Sign-In and Security → **App-Specific Passwords**
2. Click **+** → name it (e.g. "SpaceInvader CI") → Generate
3. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### Setting all secrets via CLI

```bash
base64 -i ~/Certificates.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12 -R slmingol/SpaceInvader
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD -R slmingol/SpaceInvader   # prompts for value
gh secret set APPLE_ID -R slmingol/SpaceInvader
gh secret set APPLE_TEAM_ID -R slmingol/SpaceInvader
gh secret set APPLE_ID_PASSWORD -R slmingol/SpaceInvader
```

---

## How the CI workflow signs and notarizes

The pipeline on every `v*` tag:

### 1. Import certificate into a temporary keychain

The `.p12` secret is decoded and imported into a keychain at `$RUNNER_TEMP/build.keychain`. The keychain is added to the user search list so `codesign` and `xcodebuild` can find the certificate.

**Why `$RUNNER_TEMP` not just `build.keychain`:** Using a relative path for the keychain causes `security list-keychains -s` to not find it consistently. `$RUNNER_TEMP` is a known absolute path on every GitHub Actions runner.

### 2. Build with xcodebuild

Builds the Release configuration with:
- `CODE_SIGN_STYLE=Manual` — required when specifying a certificate identity explicitly
- `CODE_SIGN_IDENTITY="Developer ID Application"` — selects the imported certificate
- `DEVELOPMENT_TEAM=<team-id>` — required by Manual signing mode; without this xcodebuild errors with "requires selecting either a development team"
- `OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH --timestamp"` — directs codesign to the temp keychain

### 3. Re-sign the app bundle for notarization

xcodebuild's `build` action injects the `com.apple.security.get-task-allow` entitlement (used for debugger attachment) even in Release builds. Apple's notary service rejects this. Additionally, Sparkle framework ships with its own pre-existing signatures on its internal XPC services and helper tools; these need to be re-signed with your Developer ID certificate.

The re-sign step works inside-out:
1. XPC services (`.xpc` bundles) inside Sparkle
2. Nested `.app` bundles (Sparkle's Updater.app)
3. Loose Mach-O helper executables (Autoupdate, etc.)
4. Frameworks (deepest paths first)
5. The main SpaceInvader.app — signed with the project's entitlements file (which does not contain `get-task-allow`)

All signatures use `--options runtime` (hardened runtime, required for notarization) and `--timestamp` (secure timestamp, required for notarization).

**Why inside-out:** codesign verifies that nested code is already signed before signing the outer bundle. Signing the outer bundle first and then a nested component would invalidate the outer signature.

### 4. Create DMG

Packages the signed `.app` into a compressed disk image with an Applications symlink for drag-install.

### 5. Notarize and staple

Submits the DMG to Apple's notary service via `xcrun notarytool --wait`. If Apple returns `Invalid`, the workflow fetches and prints the full rejection log automatically before failing — no need to run `notarytool log` manually.

After a successful notarization, `xcrun stapler staple` attaches the notarization ticket to the DMG so Gatekeeper can verify it offline without contacting Apple's servers.

### 6. Sparkle EdDSA signature

Signs the notarized DMG with the Sparkle private key for Sparkle's own update verification (separate from and in addition to Apple notarization).

---

## Triggering a release

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow fires on `v*` tag pushes. Branch pushes to `main` also trigger the workflow but skip all release steps if no version tag points at HEAD.

---

## Troubleshooting

**`Developer ID Application` not appearing in Xcode's certificate dropdown**

With `Automatically manage signing` checked, the dropdown only shows Development and "Sign to Run Locally". This is correct — Xcode handles Developer ID selection automatically at archive time. No action needed.

**Notarization returns `Invalid`**

Common causes:
- Binaries not signed with a valid Developer ID certificate — Sparkle's internal helpers must be re-signed (the CI workflow does this in the "Re-sign app for notarization" step)
- Missing secure timestamp — all `codesign` calls must include `--timestamp`
- `com.apple.security.get-task-allow` entitlement present — strip this by explicitly re-signing with the project's entitlements file (which doesn't include it)
- Hardened runtime not enabled — all binaries must be signed with `--options runtime`

The workflow prints the full Apple rejection log when notarization fails. Look for the `"message"` and `"path"` fields in the log output.

**`Signing for "SpaceInvader" requires selecting either a development team`**

This error from xcodebuild means `CODE_SIGN_STYLE=Manual` was set without `DEVELOPMENT_TEAM`. Both must be specified together.

**`gh secret set` blocked in Claude Code auto mode**

`gh secret set` requires explicit user confirmation. Run it directly in the terminal with `!` prefix (e.g. `! gh secret set ...`) or outside Claude Code entirely.

**Accessibility permission revoked after a new build**

macOS ties Accessibility permission to the code signature. Any new build with a different certificate revokes the permission for that binary. Fix: System Settings → Privacy & Security → Accessibility → toggle SpaceInvader off and back on. This happens every time the signing certificate changes.

**Notarization taking longer than 30 minutes**

Apple's notary service has no SLA. There is nothing to do but wait. The `--wait` flag in `xcrun notarytool` blocks the CI job until Apple responds (subject to the runner's job timeout of 6 hours).
