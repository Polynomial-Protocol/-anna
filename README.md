# Anna

A private, intelligent macOS assistant that helps you get things done, teaches you how apps work, and guides you visually with on-screen pointers.

Anna runs locally on your Mac. She listens when you hold a hotkey, understands your voice command, executes it (or teaches you how), speaks the response aloud, and points at UI elements on your screen to show you exactly where to click.

## Features

### Voice-Driven Interaction
- **Hold Right ⌘** — Give Anna a command (open apps, play music, search the web, automate tasks)
- **Hold Right ⌥** — Dictate text into any focused input field
- **⌘⇧Space** — Toggle the text bar for typed commands

### Visual Guidance (Clicky-style)
- Blue triangle cursor points at UI elements on your screen
- Animated pointer with label bubbles
- Coordinates parsed from Claude's response (`[POINT:x,y:label]`)
- Auto-hides after 5 seconds

### Voice Output
- Anna speaks her responses aloud using Apple's TTS
- Voice picker in Settings — choose from Premium, Enhanced, or Default voices
- Text preprocessing for natural speech (strips markdown, expands abbreviations, cleans URLs)
- Adjustable speech rate
- Preview button to audition voices before selecting

### Screen Context
- Captures your screen when you give a command (via ScreenCaptureKit)
- Sends the screenshot to Claude so it can see what you're looking at
- Enables context-aware help ("What's this button?", "How do I export from this app?")

### Teaching Mode
- Ask "How do I..." or "Show me..." and Anna explains while pointing at the relevant UI
- Conversational, spoken-first tone ("for the ear, not the eye")
- Suggests next steps to explore

### Two-Tier Execution
- **Tier 1 (Direct):** Instant local actions — media controls, volume, open apps, YouTube playback, web search
- **Tier 2 (Claude CLI):** Complex tasks delegated to Claude Code — browser automation, multi-step workflows, AppleScript, file operations

### Multi-Turn Conversation
- Anna remembers the last 10 conversation turns
- Ask follow-up questions without repeating context

### Privacy-First
- Nothing runs in the background
- Screenshots only captured when you press the hotkey
- All voice processing options available on-device
- No data sent anywhere except to Claude CLI (which runs locally)

## Screenshots

The app has a dark theme with four tabs:
- **Assistant** — Main dashboard with status, shortcuts, last transcript, streaming response, and action timeline
- **Permissions** — Request and monitor all required permissions
- **Logs** — Live log viewer with date picker and filtering
- **Settings** — Voice picker, speech rate, interaction preferences, keyboard shortcuts

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (arm64)
- [Xcode 15+](https://developer.apple.com/xcode/) with command line tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed at `~/.local/bin/claude`

## Quick Start

```bash
# 1. Clone the repo
git clone <your-repo-url> Anna
cd Anna

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode
open Anna.xcodeproj

# 4. Select your team for code signing (Xcode > Signing & Capabilities)

# 5. Build and run (⌘R)
```

## Building a DMG

```bash
# Build a distributable DMG
./Scripts/build_dmg.sh
# Output: build/Anna.dmg
```

The DMG contains `Anna.app` and an Applications symlink for drag-to-install.

> **Note:** The app is not notarized. On first launch, right-click → Open, or go to System Settings → Privacy & Security → "Open Anyway".

## Permissions

Anna requires these permissions (requested one at a time, with explanations):

| Permission | Why |
|---|---|
| **Microphone** | Hold-to-talk voice capture |
| **Accessibility** | Global hotkeys, text insertion into active fields, UI pointing |
| **Screen Recording** | Capture screen for visual context (sent to Claude) |
| **Automation** | Control Safari, Music, Finder, and other scriptable apps via AppleScript |

## Project Structure

```
Anna/
├── App/                          # Entry point and DI container
│   ├── MariaApp.swift           # @main app struct + AppDelegate
│   ├── AppContainer.swift       # Dependency injection, service wiring
│   └── RootContentView.swift    # Onboarding vs workspace routing
│
├── Core/                         # Shared foundations
│   ├── AppTheme.swift           # AnnaPalette colors, AnnaStatus enum
│   ├── AppError.swift           # AnnaError cases
│   └── ServiceProtocols.swift   # Protocol definitions
│
├── Domain/                       # Business logic
│   ├── AssistantEngine.swift    # Core orchestrator (capture → transcribe → route → execute)
│   └── IntentRouter.swift       # Two-tier intent classification
│
├── Features/                     # Feature modules (View + ViewModel)
│   ├── Assistant/               # Main dashboard
│   ├── Onboarding/              # First-run flow
│   ├── Permissions/             # Permission request UI
│   ├── Logs/                    # Live log viewer
│   └── Settings/                # Voice picker, preferences
│
├── Infrastructure/               # Platform implementations
│   ├── AI/                      # ClaudeCLIService (Claude Code wrapper)
│   ├── Audio/                   # HoldToTalkAudioRecorder
│   ├── Voice/                   # Apple Speech + Parakeet transcription
│   ├── Automation/              # DirectActionExecutor, hotkey monitor, text insertion
│   ├── Permissions/             # macOS permission checks
│   ├── Logging/                 # RuntimeLogger (daily files + in-memory buffer)
│   ├── ScreenCapture/           # ScreenCaptureKit integration
│   └── TTS/                     # TTSService (voice selection, text preprocessing)
│
├── Models/                       # Data structures
│   ├── AssistantModels.swift    # CaptureMode, ExecutionTier, AutomationOutcome, AppSettings
│   ├── PermissionModels.swift   # PermissionKind, PermissionState
│   ├── OnboardingState.swift    # Onboarding step tracking
│   ├── ClaudeCLITypes.swift     # ClaudeCLIResult
│   └── AppSettings.swift        # PushModifier enum
│
├── UIComponents/                 # Reusable SwiftUI views
│   ├── MariaWorkspaceView.swift # Sidebar + detail pane (AnnaWorkspaceView)
│   ├── ResponseBubbleView.swift # Floating response panel
│   ├── TextBarView.swift        # Floating text input panel
│   ├── PointerOverlayView.swift # Blue triangle cursor overlay
│   ├── EventRow.swift           # Action timeline row
│   ├── StatusPill.swift         # Status badge
│   ├── VoiceOrbButton.swift     # Mic button
│   ├── GlassPanel.swift         # Glassmorphic container
│   └── MenuBarView.swift        # Status bar menu
│
├── Scripts/
│   └── build_dmg.sh             # DMG packaging script
│
├── project.yml                   # XcodeGen project definition
├── README.md                     # This file
├── ARCHITECTURE.md               # Detailed architecture guide
├── SETUP.md                      # Step-by-step setup instructions
└── .gitignore
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for a detailed breakdown of the codebase, data flow, and design decisions.

## Setup Guide

See [SETUP.md](SETUP.md) for step-by-step instructions on setting up your development environment, configuring permissions, and downloading voice models.

## How It Works

### Voice Command Flow

```
User holds Right ⌘
  ↓
ModifierKeyMonitor detects keypress
  ↓
HoldToTalkAudioRecorder starts recording (16kHz mono AAC)
  ↓
ScreenCaptureService captures screen (PNG)
  ↓
User releases Right ⌘
  ↓
Audio → Apple Speech Recognition → transcript
  ↓
IntentRouter classifies: Direct action or Claude CLI?
  ↓
├── Direct: execute immediately (media, volume, open app, YouTube, search)
└── Claude CLI: send transcript + screenshot + conversation history
      ↓
      Claude responds with text + optional [POINT:x,y:label]
      ↓
      ├── Response displayed with streaming animation
      ├── TTSService speaks response (preprocessed for natural speech)
      └── PointerOverlayManager shows blue triangle at coordinates
```

### AI Backend

Anna uses the **Claude CLI** (`claude` command) running locally. Each voice command invokes:

```bash
claude -p "<prompt>" \
  --dangerously-skip-permissions \
  --system-prompt "<teaching + pointing instructions>" \
  --output-format json \
  --model sonnet \
  --no-session-persistence
```

This means Claude Code has full access to your system (bash, AppleScript, browser control) to execute tasks. The `--dangerously-skip-permissions` flag is required for hands-free automation.

## Configuration

All settings are persisted to UserDefaults and survive app restarts:

- **Voice selection** — Choose from installed Premium/Enhanced/Default voices
- **Speech rate** — Adjustable slider (0.3 to 0.65)
- **TTS on/off** — Toggle spoken responses
- **Purchase confirmation** — Safety gate for financial actions
- **Route reuse** — Cache successful action routes

## License

Private project by Damien Jacob.
