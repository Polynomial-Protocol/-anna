# Architecture Guide

## Overview

Anna is a native macOS SwiftUI application that acts as a voice-driven assistant with visual guidance capabilities. The architecture follows a clean separation of concerns with protocol-driven design for testability.

## Layer Diagram

```
┌──────────────────────────────────────────────────┐
│                    App Layer                      │
│  AnnaApp.swift, AppContainer.swift,               │
│  RootContentView.swift                            │
│  (Entry point, DI container, root view routing)   │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│                Features Layer                     │
│  AssistantView/VM, OnboardingView,                │
│  PermissionCenterView/VM, LogsView,               │
│  SettingsView/VM                                  │
│  (UI + ViewModels, feature-specific logic)        │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│                 Domain Layer                      │
│  AssistantEngine (actor), IntentRouter            │
│  (Core business logic, orchestration)             │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│             Infrastructure Layer                  │
│  ClaudeCLIService, HoldToTalkAudioRecorder,       │
│  AppleSpeechTranscriptionService,                 │
│  DirectActionExecutor, MacPermissionService,       │
│  ScreenCaptureService, TTSService,                │
│  ModifierKeyMonitor, RuntimeLogger                │
│  (Platform-specific implementations)              │
└──────────────────────────────────────────────────┘
```

## Dependency Injection

`AppContainer` is the single DI container, created once at app launch via `AppContainer.live()`. It holds all services and view models, and is passed to the view hierarchy via `.environmentObject()`.

```swift
AppContainer.live()
  ├── MacPermissionService
  ├── HoldToTalkAudioRecorder
  ├── AppleSpeechTranscriptionService
  ├── FluidAudioSpeechModelService
  ├── ActiveTextInsertionService
  ├── ScreenCaptureService
  ├── TTSService
  ├── ModifierKeyMonitor
  ├── AssistantEngine (actor)
  │   ├── audioCaptureService
  │   ├── voiceService
  │   ├── textInsertionService
  │   ├── screenCaptureService
  │   ├── directExecutor (DirectActionExecutor)
  │   └── claudeCLI (ClaudeCLIService)
  ├── ResponseBubbleController
  ├── TextBarController
  ├── PointerOverlayManager
  └── RuntimeLogger
```

## State Management

Anna uses SwiftUI's native state management:

- **`@Published`** properties on `ObservableObject` ViewModels
- **`@EnvironmentObject`** for passing `AppContainer` down the view tree
- **`@ObservedObject`** for ViewModel references in views
- **`@State`** for view-local state

No Redux, MVI, or third-party state management libraries.

## Key Design Decisions

### 1. Actor for AssistantEngine

`AssistantEngine` is a Swift `actor` to ensure thread safety during audio capture, transcription, and execution. Multiple hotkey events could fire in quick succession — the actor serializes them.

### 2. Protocol-Based Services

All services conform to protocols (`PermissionService`, `AudioCaptureService`, `VoiceTranscriptionService`, etc.) defined in `Core/ServiceProtocols.swift`. This enables:
- Easy mocking for tests
- Swappable implementations (e.g., Parakeet vs Apple Speech)

### 3. Two-Tier Intent Routing

`IntentRouter` uses simple string matching for Tier 1 (direct actions) before falling back to Tier 2 (Claude CLI). This means common commands like "play", "pause", "open Safari" execute instantly without waiting for Claude.

### 4. Claude CLI over Claude API

Anna uses the local `claude` CLI binary instead of the Claude API directly. This provides:
- No API key management
- Full tool access (bash, filesystem, browser control)
- No network dependency for the AI call itself
- Matches the user's existing Claude Code setup

Trade-off: no streaming responses from Claude (batch output only).

### 5. Floating Panels (NSPanel)

The response bubble, text bar, and pointer overlay use `NSPanel` subclasses instead of SwiftUI windows. This allows:
- Non-activating panels (don't steal focus from the user's active app)
- Status bar / screen saver level windows
- Cross-space visibility
- Mouse-through for the pointer overlay

### 6. Settings Persistence

`AppSettings` is `Codable` and saved as JSON to `UserDefaults`. The `didSet` on `AppContainer.settings` triggers automatic saves.

## Data Flow

### Voice Command

```
ModifierKeyMonitor.onCommandPressed
  → AppContainer.configureHotkeysIfNeeded() callbacks
    → AssistantViewModel.beginCapture(mode:)
      → AssistantEngine.beginCapture(mode:)
        → HoldToTalkAudioRecorder.beginCapture()

ModifierKeyMonitor.onCommandReleased
  → AssistantViewModel.endCapture()
    → AssistantViewModel.doEndCapture()
      → AssistantEngine.finishCapture()
        → HoldToTalkAudioRecorder.finishCapture() → CapturedUtterance
        → AppleSpeechTranscriptionService.transcribe() → TranscriptionResult
        → IntentRouter.route() → ExecutionTier
        → [if .direct] DirectActionExecutor.execute() → AutomationOutcome
        → [if .agent]  ScreenCaptureService.captureToFile()
                        ClaudeCLIService.execute() → ClaudeCLIResult
                        Parse [POINT:x,y] → PointerCoordinate?
      → AssistantViewModel updates UI
        → animateStreamingText()
        → PointerOverlayManager.pointAt() (if coordinates present)
        → TTSService.speak() (if TTS enabled)
```

### Dictation

```
ModifierKeyMonitor.onOptionPressed
  → beginCapture(mode: .dictation)
    → record audio

ModifierKeyMonitor.onOptionReleased
  → endCapture()
    → transcribe audio
    → check if media is playing (skip insertion if yes)
    → ActiveTextInsertionService.insertText()
      → clipboard + Cmd+V keystroke
```

## File Naming Conventions

- **Views:** `FooView.swift` — SwiftUI views
- **ViewModels:** `FooViewModel.swift` — `@MainActor ObservableObject`
- **Services:** `FooService.swift` — Infrastructure implementations
- **Models:** `FooModels.swift` — Data structures and enums

## Concurrency Model

- **Main actor:** All UI code, ViewModels, Controllers, TTSService
- **Actor:** AssistantEngine (serializes capture/transcribe/execute)
- **Nonisolated:** AVSpeechSynthesizerDelegate callbacks (bridge to main actor via Task)
- **DispatchQueue:** Audio recording queue, Claude CLI timeout handling

## Logging

`RuntimeLogger` writes to:
- **Console:** `print()` for Xcode debugging
- **Memory:** 500-line circular buffer for the live log viewer
- **Disk:** `~/.anna/logs/anna-YYYY-MM-DD.log` daily files

Tags: `[app]`, `[hotkey]`, `[capture]`, `[voice]`, `[action]`, `[permission]`
