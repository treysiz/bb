# MiniBridge Password for iPhone

## Camera/audio internal-test app (source only)

The same project now includes an independent **MiniBridge Camera** shared scheme.
It uses the existing NAS member portal through WKWebView, with landscape support,
explicit media playback, safe lifecycle cleanup and native file sharing. Select
this scheme to test the camera; it has no dependency on the Password/AutoFill
targets or their entitlements. See [the iPhone build/install checklist](../docs/IOS_CAMERA_TESTFLIGHT.md).
Native compilation, signing, IPA generation, TestFlight upload and iPhone media
tests are NOT_RUN on this Windows workstation. The source package is not an IPA.
For the prepared cloud macOS compile-only workflow, see [cloud build steps](../docs/IOS_CLOUD_BUILD.md).
No source has been published or cloud job started.

The original password application below remains separate and unchanged.

Native iOS host app and Authentication Services Credential Provider extension.
The companion app pairs to the existing `/vault` WebSocket with a one-time
code. The extension handles Apple's system password-save request and credential
selection for Safari and apps; users can keep or dismiss each proposed login.
Saved rows use the server vault's existing PBKDF2-SHA256/AES-GCM wire format.

## Setup and build

Open `MiniBridgePassword.xcodeproj` on a Mac with Xcode 16 or newer. Select a
development team for both targets, enable the Password AutoFill Credential
Provider capability for the host app and extension, and make sure the team
provisions the required Authentication Services entitlement and shared Keychain
access group. Build to a signed iPhone, open the app, pair using a code from the
MiniBridge web vault, unlock with the same vault master password, then enable
MiniBridge Password under Settings → General → AutoFill & Passwords.

The iOS target is source-only in this Windows workspace: Xcode signing,
entitlement provisioning, installation and iPhone testing must be completed on
macOS. Use a trusted public HTTPS/WSS certificate. The extension asks for
Face ID/device authentication before reading the vault key. No ESP32 firmware
change is needed.

Current source uses the Apple `ASSavePasswordRequest` flow, which presents the
credential-provider extension UI for an explicit Save or Cancel choice. Apple
may only invoke that flow when the website or app reports a password event to
Password AutoFill; that behavior must be tested on the real phone.

The repository includes the Xcode project, app and extension targets, and
shared Keychain entitlements. On macOS, choose a development team for both
targets and enable the Password AutoFill Credential Provider capability so
Xcode provisions the matching Apple entitlement. Windows cannot run Apple's
Xcode build, signing, provisioning, installation, or iPhone tests.
