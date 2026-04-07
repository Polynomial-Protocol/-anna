# Setup Guide

Step-by-step instructions for setting up Anna on your Mac.

## Prerequisites

### 1. Install Xcode

Download from the Mac App Store or [developer.apple.com/xcode](https://developer.apple.com/xcode/).

After installation, install command line tools:
```bash
xcode-select --install
```

### 2. Install XcodeGen

```bash
brew install xcodegen
```

XcodeGen generates the `.xcodeproj` from `project.yml`, so the Xcode project file is never committed to git.

### 3. Install Claude CLI

Anna requires the Claude CLI (`claude` command) for complex task execution.

```bash
# Install via npm
npm install -g @anthropic-ai/claude-code

# Or via the official installer
# See: https://docs.anthropic.com/en/docs/claude-code
```

Verify it's installed:
```bash
which claude
# Expected: /Users/<you>/.local/bin/claude (or similar)
```

If your `claude` binary is at a different path, update the path in `Infrastructure/AI/ClaudeCLIService.swift`:
```swift
init(claudePath: String = "/Users/<you>/.local/bin/claude", ...)
```

### 4. Authenticate Claude

```bash
claude auth login
```

## Building the Project

### Generate Xcode Project

```bash
cd Anna
xcodegen generate
```

This creates `Anna.xcodeproj`.

### Open in Xcode

```bash
open Anna.xcodeproj
```

### Configure Code Signing

1. Select the **Anna** target in Xcode
2. Go to **Signing & Capabilities**
3. Select your **Team** (personal or organization)
4. Xcode will auto-create a signing certificate

### Build and Run

Press **⌘R** or click the Play button.

## Granting Permissions

On first launch, Anna will guide you through permissions. You can also set them up manually:

### Microphone

Anna will prompt automatically on first voice capture. Click **Allow**.

If denied, re-enable at:
**System Settings → Privacy & Security → Microphone → Anna**

### Accessibility

Required for global hotkeys and text insertion.

1. Anna will open the Accessibility prompt automatically
2. If it doesn't appear, go to:
   **System Settings → Privacy & Security → Accessibility**
3. Click the **+** button and add Anna
4. Toggle it **ON**

> **Important:** You may need to quit and relaunch Anna after granting Accessibility.

### Screen Recording

Required for Anna to see your screen and provide visual guidance.

1. Go to **System Settings → Privacy & Security → Screen Recording**
2. Click the **+** button and add Anna
3. Toggle it **ON**
4. Restart Anna

### Automation

Granted automatically per-app when Anna first tries to control an app (Safari, Music, etc.). macOS will show a prompt like "Anna wants to control Safari" — click **OK**.

## Configuring Voice

### Download Better Voices

The default macOS voices sound robotic. Download Premium voices for much better quality:

1. Open **System Settings → Accessibility → Spoken Content**
2. Click **System Voice** dropdown → **Manage Voices...**
3. Download recommended voices:
   - **Zoe (Premium)** — Natural, warm female voice (best overall)
   - **Ava (Premium)** — Smooth female voice
   - **Tom (Premium)** — Clear male voice
   - **Kate (Premium)** — British female voice

4. In Anna, go to **Settings → Voice** and select your preferred voice
5. Click **Preview** to hear it before selecting

### Adjust Speech Rate

In **Settings → Voice**, use the speech rate slider:
- **0.35** — Slow, deliberate (good for learning)
- **0.50** — Normal conversational speed (default)
- **0.60** — Fast (experienced users)

## Building a DMG for Distribution

```bash
./Scripts/build_dmg.sh
```

This will:
1. Generate the Xcode project
2. Archive a Release build
3. Package it into `build/Anna.dmg`

The DMG contains the app bundle and an Applications symlink for drag-and-drop installation.

### Gatekeeper Warning

Since the app is not notarized, recipients will see a Gatekeeper warning. To open:
- **Right-click** the app → **Open** → **Open** again
- Or: **System Settings → Privacy & Security → "Open Anyway"**

## Uninstalling

To cleanly uninstall and remove all data:

```bash
# Remove the app
rm -rf /Applications/Anna.app

# Remove logs
rm -rf ~/.anna

# Remove preferences
defaults delete com.damienjacob.anna

# Remove TCC entries (optional, requires admin)
# This clears permission grants from the system database
sudo tccutil reset Microphone com.damienjacob.anna
sudo tccutil reset Accessibility com.damienjacob.anna
sudo tccutil reset ScreenCapture com.damienjacob.anna
```

## Troubleshooting

### "Claude CLI not found"

Make sure `claude` is in your PATH:
```bash
which claude
```

If it's installed but not found, update the path in `ClaudeCLIService.swift` or add it to your shell profile:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Hotkeys not working

- Ensure **Accessibility** permission is granted
- Quit and relaunch Anna after granting
- Check that no other app is capturing Right ⌘ / Right ⌥

### No voice output

- Check **Settings → Voice → Speak responses aloud** is toggled on
- Make sure your Mac's volume is not muted
- Try selecting a different voice in the voice picker

### Screen capture not working

- Ensure **Screen Recording** permission is granted
- You must restart Anna after granting this permission
- Check **System Settings → Privacy & Security → Screen Recording → Anna** is toggled on

### Permissions stuck after reinstall

macOS caches TCC permissions. If they're stale after reinstalling:
```bash
sudo tccutil reset All com.damienjacob.anna
```
Then relaunch Anna and re-grant permissions.

## Development Tips

### Logs

Anna writes detailed logs to `~/.anna/logs/`. You can also view them live in the **Logs** tab within the app.

### Regenerating the Xcode Project

If you add new files or change `project.yml`:
```bash
xcodegen generate
```

### Adding a New Source File

1. Create the `.swift` file in the appropriate directory
2. Run `xcodegen generate` — it auto-discovers files from the directories listed in `project.yml`
3. Open the project in Xcode

### Testing Voice Commands Without a Microphone

Use the text bar (⌘⇧Space) to type commands instead of speaking them. Note: the text bar currently triggers `beginCapture` which expects audio — for typed-only input, use the Claude CLI directly in terminal for testing.
