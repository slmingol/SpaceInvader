# Code Signing & Notarization

This document covers how SpaceInvader is signed, notarized, and distributed outside the Mac App Store, and how to reproduce the setup from scratch.

---

## Prerequisites

- An Apple Developer Program membership ($99/year) enrolled at developer.apple.com
- Xcode installed with your Apple ID added under Settings → Apple Accounts
- `gh` CLI authenticated (`gh auth login`)

---

## One-time local setup

### 1. Add your Apple ID to Xcode

Xcode → Settings (Cmd+,) → Apple Accounts → click **+** → Apple ID → sign in.

Once added, select the account and click **Download Manual Profiles** to sync certificates and profiles.

### 2. Create a Developer ID Application certificate

In the same Apple Accounts screen, click the team row → **Manage Certificates** → click **+** → **Developer ID Application**.

Xcode generates the certificate and stores it in your login keychain. This is the certificate used for distributing apps outside the App Store.

> Note: `Automatically manage signing` in Xcode uses the **Development** certificate for local builds. The Developer ID Application certificate is only selected automatically when you Archive for distribution. This is expected — do not change the Signing Certificate dropdown for day-to-day development.

### 3. Archive and notarize locally (one-off)

To produce a signed, notarized build from Xcode:

1. Set the run destination to **My Mac** (not a simulator)
2. Product → **Archive**
3. Organizer opens — click **Distribute App**
4. Choose **Direct Distribution**
5. Xcode uploads to Apple's notary service automatically
6. When status shows **Ready to distribute**, click **Export Notarized App**

Notarization typically takes 5–30 minutes depending on Apple server load. Xcode polls in the background — you do not need to keep Organizer open. A macOS notification fires when complete (System Settings → Notifications → Xcode must be enabled).

---

## CI/CD setup (GitHub Actions)

The release workflow handles signing and notarization automatically on every version tag push.

### Secrets required

Add these under your GitHub repo → Settings → Secrets and variables → Actions:

| Secret | Description |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate exported from Keychain |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` |
| `APPLE_ID` | Your Apple ID email address |
| `APPLE_ID_PASSWORD` | App-specific password (not your Apple ID password — see below) |
| `APPLE_TEAM_ID` | Your 10-character team ID (visible in Xcode target → Signing & Capabilities, or in the certificate name) |

### Exporting the certificate

1. Open **Keychain Access** → select the **login** keychain → **My Certificates** tab
2. Right-click **Developer ID Application: Your Name (TEAMID)** → **Export**
3. Save as a `.p12` file with a strong password
4. Base64-encode it and pipe directly to `gh secret set`:

```bash
base64 -i ~/Certificates.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12 -R your-org/SpaceInvader
```

### App-specific password

Apple requires a dedicated app-specific password for automated notarization — your main Apple ID password will not work.

1. Go to **appleid.apple.com** → Sign-In and Security → **App-Specific Passwords**
2. Click **+** → name it (e.g. "SpaceInvader CI") → Generate
3. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)
4. Set it as the `APPLE_ID_PASSWORD` secret

### Setting all secrets via CLI

```bash
base64 -i ~/Certificates.p12 | gh secret set DEVELOPER_ID_CERTIFICATE_P12 -R slmingol/SpaceInvader
gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD -R slmingol/SpaceInvader
gh secret set APPLE_ID -R slmingol/SpaceInvader
gh secret set APPLE_TEAM_ID -R slmingol/SpaceInvader
gh secret set APPLE_ID_PASSWORD -R slmingol/SpaceInvader
```

Each command prompts for the value securely.

### How the workflow signs and notarizes

The release workflow (`.github/workflows/release.yml`) performs these steps on every `v*` tag push:

1. **Import certificate** — decodes the `.p12` secret into a temporary keychain scoped to the build runner
2. **Build** — `xcodebuild` picks up the Developer ID Application certificate automatically via the keychain
3. **Create DMG** — packages the signed `.app` with an Applications symlink
4. **Notarize** — submits the DMG to Apple's notary service via `xcrun notarytool --wait`; blocks until Apple returns a result
5. **Staple** — attaches the notarization ticket to the DMG so Gatekeeper can verify offline (`xcrun stapler staple`)
6. **Sparkle signature** — signs the DMG with the Sparkle EdDSA key for update verification
7. **Upload** — attaches the DMG to the GitHub release

### Triggering a release

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow detects the tag, uses it as the version number, and runs the full sign → notarize → release pipeline.

---

## Troubleshooting

**Developer ID Application not appearing in Xcode certificate dropdown**
The dropdown only shows Development and Sign to Run Locally when Automatically manage signing is on. This is correct — Developer ID is applied at archive time, not during local builds.

**Notarization taking longer than 30 minutes**
Apple's notary service can be slow under load. There is no action to take — it will complete eventually. The `--wait` flag in `xcrun notarytool` will block the CI job until Apple responds (up to the runner's job timeout).

**Accessibility permission revoked after rebuild**
macOS ties Accessibility permission to the code signature. Any rebuild with a different certificate revokes the permission for the new binary. Fix: System Settings → Privacy & Security → Accessibility → toggle SpaceInvader off and back on.

**`gh secret set` permission denied in Claude Code**
The `gh secret set` command requires explicit user confirmation in Claude Code's auto mode. Run the command directly in your terminal with `!` prefix or outside Claude Code.
