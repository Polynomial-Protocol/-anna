# Anna — Release Checklist

## Build Process

```bash
# 1. Generate project and build DMG (unsigned, for local testing)
./Scripts/build_dmg.sh

# 2. Build signed DMG (requires Developer ID certificate)
./Scripts/build_dmg.sh --sign

# 3. Notarize (after signing)
xcrun notarytool submit build/Anna.dmg \
    --keychain-profile "AC_PASSWORD" --wait

# 4. Staple the notarization ticket to the DMG
xcrun stapler staple build/Anna.dmg

# 5. Verify
spctl --assess --type open --context context:primary-signature build/Anna.dmg
```

## Pre-Release Checklist

- [ ] Version bumped in `project.yml` (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`)
- [ ] All permissions working: Microphone, Accessibility, Screen Recording, Automation
- [ ] Onboarding flow completes cleanly on fresh install
- [ ] Permission Center shows correct states after granting/denying
- [ ] Menu bar icon appears and responds to left-click (open) and right-click (menu)
- [ ] App does not appear in Dock when window is closed
- [ ] App activates properly when clicking menu bar icon or reopening
- [ ] Hotkeys work: Right Cmd (agent), Right Option (dictation)
- [ ] DMG opens with clean drag-to-Applications layout
- [ ] App launches correctly from /Applications after drag-install
- [ ] App icon displays correctly in Finder, Launchpad, and System Settings
- [ ] TTS (Piper) works after install from Applications
- [ ] Claude CLI integration works
- [ ] No crash on first launch with no permissions granted
- [ ] Denying all permissions shows recovery UI, app doesn't break

## TCC Reset for Testing

To test fresh permission flows, reset TCC entries for Anna:

```bash
# Reset all Anna permissions (requires SIP disabled or MDM)
tccutil reset All com.polynomial.anna

# Or reset individually:
tccutil reset Microphone com.polynomial.anna
tccutil reset Accessibility com.polynomial.anna
tccutil reset ScreenCapture com.polynomial.anna
tccutil reset AppleEvents com.polynomial.anna
```

Note: On macOS 14+, tccutil may require Full Disk Access or SIP adjustments.
For testing, the easiest approach is to delete and reinstall the app, which
causes macOS to treat it as a new app for permission purposes.

## Architecture Notes

- **Menu bar app**: `LSUIElement = true` in Info.plist hides the Dock icon.
  The app uses `NSApp.setActivationPolicy(.regular)` temporarily when
  showing windows, then reverts to `.accessory` when they close.

- **Hardened Runtime**: Enabled with entitlements for audio input, AppleEvents,
  JIT (for ONNX models), and library validation disabled (for piper dylibs).

- **No App Sandbox**: Anna requires system-wide accessibility, screen capture,
  and automation access that sandboxed apps cannot obtain.

## Manual Steps

*These require your Apple Developer account and cannot be automated without credentials.*

### 1. Apple Developer Account Setup

- Enroll at [developer.apple.com](https://developer.apple.com) ($99/year)
- Create a **Developer ID Application** certificate in Certificates, Identifiers & Profiles
- Download and install the certificate in your Mac's Keychain

### 2. Select Signing Team in Xcode

- Open `Anna.xcodeproj` in Xcode
- Select the Anna target > Signing & Capabilities
- Choose your Team from the dropdown
- Xcode will auto-manage provisioning

### 3. Update ExportOptions.plist

- Edit `Scripts/ExportOptions.plist`
- Replace `YOUR_TEAM_ID` with your 10-character Apple Team ID
  (find it at developer.apple.com > Membership)

### 4. Set Up Notarization Credentials

Store your App Store Connect credentials in the keychain for scripted notarization:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password"
```

Generate the app-specific password at [appleid.apple.com](https://appleid.apple.com)
under Sign-In and Security > App-Specific Passwords.

### 5. First Signed Build

```bash
./Scripts/build_dmg.sh --sign
xcrun notarytool submit build/Anna.dmg --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple build/Anna.dmg
```

### 6. Verify Distribution

```bash
# Check the DMG passes Gatekeeper
spctl --assess --type open --context context:primary-signature build/Anna.dmg

# Check the app inside passes Gatekeeper
spctl --assess --verbose build/export/Anna.app
```

### 7. Test on a Clean Mac

- Copy the DMG to another Mac (or a clean user account)
- Double-click to mount — verify the drag-to-Applications window appears
- Drag to Applications
- Launch from Applications — verify no Gatekeeper warnings
- Complete onboarding — verify all permission prompts appear correctly
- Test all features
