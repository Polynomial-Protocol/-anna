# Claude Code Prompt: Anna — Self-Growing macOS Tutor App

> Paste this entire document into Claude Code as your starting session prompt.
> This is a CLAUDE.md-style instruction file and session briefer combined.

---

## Who you are working with

You are building **Anna** — a macOS AI assistant that watches what the user is doing across apps and teaches them how to do things, provides first-launch onboarding, and gives full walkthroughs on demand. It is built in SwiftUI and targets macOS 14+. The app should have a quiet, minimal aesthetic (think: floating sidebar, never in the way, never noisy).

The app already exists as a SwiftUI project. Your job is to significantly improve it along multiple dimensions described below. Read the entire document before writing a single line of code.

---

## Mental model: what this app actually is

Before you touch any files, internalize this framing:

Anna is a **macOS-native AI agent with a self-compiling knowledge brain**. Every session teaches it something new. Every interaction either confirms or refines what it knows. It is never static. Think of it the way Andrej Karpathy described his LLM Knowledge Base: raw inputs → LLM compiles them → structured wiki → the wiki is what gets queried next time. Not a RAG pipeline that retrieves and forgets, but a system that **accumulates and compounds**.

The three-layer knowledge architecture you must implement:

```
raw/          ← everything observed (screen states, user queries, accessibility snapshots)
wiki/         ← compiled, structured knowledge (per-app articles, how-tos, patterns)
schema.md     ← rules for how the LLM treats and evolves the wiki (the most important file)
```

The LLM (Claude API) does the compilation step. Anna watches → observes → compiles into wiki → serves wiki when user needs help → logs what worked → lints the wiki periodically to remove rot.

---

## Architecture to implement (four layers)

### Layer 1 — Perception (reading the screen)

Implement a `PerceptionEngine` class in Swift that runs as a background service.

**Primary path: AXUIElement (Accessibility Tree)**

```swift
// Use NSWorkspace to detect frontmost app
let frontApp = NSWorkspace.shared.frontmostApplication
let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

// Read the full UI hierarchy
func readAccessibilityTree(_ element: AXUIElement, depth: Int = 0) -> [UINode] {
    // recurse through children, extract:
    // - role (AXRole)
    // - title / description (AXTitle, AXDescription)  
    // - value (AXValue)
    // - position + size (AXPosition, AXSize)
    // - enabled / focused state
}
```

Serialize the result to a compact JSON snapshot. Keep it under 4KB by pruning redundant nodes and cutting anything below depth 5 unless it's interactive.

**Fallback path: Screenshot + Vision (for Electron apps)**

Electron apps (VS Code, Slack, Notion, Figma, Discord) return empty accessibility trees. For these, fall back to:
1. Capture a screenshot with `CGWindowListCreateImage`
2. Send to Claude API with vision enabled as a base64 image
3. Ask Claude to describe the current UI state and extract interactive elements

Detect Electron apps by checking bundle identifier patterns: `com.microsoft.VSCode`, `com.tinyspeck.slackmacgap`, `com.figma.Desktop`, `com.discord`, etc. Keep a plist of known Electron app bundle IDs.

**App detection and state change triggers**

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification
) { notification in
    // New app focused — check if first time ever
    // If first time: trigger onboarding
    // If returning: check if context changed significantly
}
```

Track app open count per bundle ID in UserDefaults. If count == 1, it's a first launch. Trigger onboarding pipeline immediately.

---

### Layer 2 — Knowledge Base (the self-growing brain)

This is the most important layer. Implement using Karpathy's three-layer wiki architecture adapted for macOS:

**File structure** (store in `~/Library/Application Support/Anna/`):

```
Anna/
├── raw/
│   ├── sessions/           ← per-session observation logs (JSON)
│   ├── queries/            ← user questions that came in
│   └── gaps/               ← questions that weren't answered well
├── wiki/
│   ├── index.md            ← master table of contents
│   ├── log.md              ← append-only operation log
│   └── apps/
│       ├── figma.md        ← compiled knowledge for Figma
│       ├── xcode.md        ← compiled knowledge for Xcode
│       ├── vscode.md       ← ...
│       └── [app-name].md   ← one file per app ever seen
└── schema.md               ← THE MOST IMPORTANT FILE — rules for the LLM
```

**schema.md (generate this file on first run):**

```markdown
# Anna Knowledge Base Schema

## Page types
- App pages (wiki/apps/[name].md): Everything Anna knows about a specific app
- Gap pages (wiki/gaps/[topic].md): Unsolved user questions worth investigating

## App page structure
Each app page must have:
- ## Overview: what this app is for, user personas
- ## First launch: the 5 most important things to show a new user
- ## Key workflows: task-oriented sections (not UI-section-oriented)
- ## Common confusions: things users get stuck on frequently
- ## Keyboard shortcuts: the most valuable 10
- ## Confidence: 0-100 score. Below 40 = unreliable, flag for improvement

## Ingest rules
- Every observation session gets stored in raw/sessions/ as JSON
- When a query is answered well (user continued task), extract insight and update wiki/apps/[name].md
- When a query fails (user ignored tip, dismissed, or asked again), log to raw/gaps/
- Never delete from raw/. Only add.
- Wiki pages get recompiled (not just appended) when confidence drops or new sessions add 5+ new data points

## Lint rules (run weekly)
- Check every app page has all required sections
- Flag any claim that hasn't been confirmed by a real session in 90+ days as stale
- Check for contradictions across app pages (e.g., same shortcut listed differently)
- Output lint report to wiki/log.md

## Confidence scoring
- +5 for each session where advice was followed
- +10 for each successful walkthrough completion
- -10 for each gap logged against this app
- -5 for each dismissed tip
```

**KnowledgeBase Swift class:**

```swift
class KnowledgeBase: ObservableObject {
    let baseURL: URL  // ~/Library/Application Support/Anna/
    
    // Query: find relevant knowledge for current app + screen state
    func query(app: String, screenContext: String, userQuery: String?) async -> KBResult {
        // 1. Read wiki/apps/[app].md if exists
        // 2. If confidence < 40 or file doesn't exist, also include raw session snippets
        // 3. Return struct with: articles [String], confidence: Int, gaps: [String]
    }
    
    // Ingest: process a session after it ends
    func ingest(session: ObservationSession) async {
        // 1. Append session to raw/sessions/
        // 2. Call Claude API to compile new insights into wiki/apps/[app].md
        // 3. Update confidence score
        // 4. Check if lint threshold reached (5+ new sessions since last lint)
    }
    
    // Lint: run health check on entire wiki
    func lint() async {
        // 1. Load schema.md + all wiki/apps/*.md
        // 2. Call Claude API with lint prompt
        // 3. Apply suggested fixes, log to wiki/log.md
    }
    
    // Gap logging
    func logGap(query: String, app: String, reason: GapReason) {
        // Append to raw/gaps/ and update app confidence score
    }
}
```

**The compilation prompt** (used when ingesting a session):

```
You are Anna's knowledge compiler. Your job is to update the knowledge base for [APP_NAME].

Current wiki page:
---
[EXISTING_WIKI_PAGE_CONTENT or "Does not exist yet"]
---

New raw session data (what the user was doing, what advice was given, what worked):
---
[SESSION_JSON_SUMMARY]
---

Schema rules you must follow:
---
[SCHEMA_MD_CONTENT]
---

Task: Update the wiki page for [APP_NAME]. 
- Integrate any new genuine insights from the session.
- Do NOT add speculative content. Only add things confirmed by the session.
- Update the confidence score based on the session outcome.
- Preserve all existing content that is still valid.
- Return the complete updated wiki page as markdown. Nothing else.
```

---

### Layer 3 — Reasoning (generating help)

**TutorialEngine** class that wraps Claude API calls:

```swift
class TutorialEngine {
    
    // Onboarding: triggered on first launch of any app
    func generateOnboarding(app: AppInfo, screenState: UISnapshot) async -> Tutorial {
        let knowledge = await KnowledgeBase.shared.query(app: app.name, ...)
        
        let prompt = """
        You are Anna, a quiet macOS tutor. The user just opened \(app.name) for the first time.
        
        What you know about this app:
        \(knowledge.articles.joined(separator: "\n\n"))
        
        Current screen state:
        \(screenState.compactDescription)
        
        Generate a 5-step first-launch orientation. Each step should:
        - Be one sentence of what to notice + one sentence of what to do
        - Reference actual UI elements visible on screen if possible  
        - Build sequentially (don't jump around)
        - Never be condescending
        
        Format as JSON:
        { "steps": [{ "title": "...", "body": "...", "highlight": "element name or null" }] }
        """
        
        // Call Claude API, parse JSON, return Tutorial struct
    }
    
    // Contextual tip: triggered when screen state changes significantly
    func generateContextualTip(app: AppInfo, screenState: UISnapshot, prevState: UISnapshot?) async -> Tip? {
        // Only fire if delta between states is meaningful
        // Return nil if no valuable tip exists (do not hallucinate help)
        // Use confidence threshold: if KB confidence < 40, skip tip
    }
    
    // Walkthrough: triggered by explicit user request  
    func generateWalkthrough(task: String, app: AppInfo, screenState: UISnapshot) async -> Walkthrough {
        // Generate step-by-step guide for a specific task
        // Reference actual screen elements
        // Return Walkthrough with steps that can be advanced one at a time
    }
}
```

**Critical constraint on tip generation:** Never generate a tip if the knowledge base confidence for the current app is below 40. Log it as a gap instead. A gap is better than a hallucinated tip.

---

### Layer 4 — Self-Improvement Loop

This runs continuously in the background. Implement as a `LearningLoop` actor:

```swift
actor LearningLoop {
    
    // Called when user follows a suggestion (continued the task)
    func recordSuccess(session: Session) {
        session.app.confidence += 10
        await KnowledgeBase.shared.ingest(session: session)
    }
    
    // Called when user dismisses/ignores a tip
    func recordDismissal(tip: Tip) {
        tip.app.confidence -= 5
        KnowledgeBase.shared.logGap(query: tip.context, app: tip.app, reason: .dismissed)
    }
    
    // Called when user asks a question that wasn't answered well
    func recordGap(query: String, app: String) {
        KnowledgeBase.shared.logGap(query: query, app: app, reason: .unanswered)
    }
    
    // Weekly background lint — schedule via BackgroundTasks framework
    func scheduledLint() async {
        let daysSinceLastLint = UserDefaults.standard.integer(forKey: "lastLintDay")
        if daysSinceLastLint >= 7 {
            await KnowledgeBase.shared.lint()
        }
    }
}
```

---

## UI requirements (quiet, minimal, Anna aesthetic)

The UI must feel like a ghost living on the mac — present when needed, invisible otherwise.

**Main window:** A narrow floating panel. Use `.NSFloatingWindowLevel` + `NSPanel`. Width: 320pt. Height: dynamic. Position: right edge of screen by default, user can drag.

**Visual style:**
- Background: `NSVisualEffectView` with `.hudWindow` material — frosted glass
- Text: SF Pro, 13pt for body, 11pt for hints
- No drop shadows on the panel itself
- Accent: single tint color, user-configurable
- Animations: only `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))`
- No emoji in UI (except for deliberately chosen single-purpose icons)

**Trigger mechanism:**
- Global hotkey: `⌘ + Shift + A` — opens Anna wherever the user is
- Auto-trigger: on first-launch detection (silent notification, not a popup)
- Passive mode: a tiny (8pt) dot indicator in the menu bar that pulses when Anna has a tip ready

**Tip display:**
- One-liner tip shown as a small card that slides in from the right edge
- "Tell me more" button expands to full walkthrough
- "Not now" dismisses and logs the dismissal
- "Never show for this app" suppresses all tips for that app

**Onboarding UI:**
- Five-step stepper shown in the Anna panel
- Progress dots at top
- Previous / Next navigation
- Each step can highlight a UI element (show a subtle ring overlay using `CGRect` from accessibility data)

---

## Swift package dependencies to add

```swift
// Package.swift additions:
.package(url: "https://github.com/rryam/VecturaKit", from: "1.0.0"),
// VecturaKit: on-device Swift vector database for semantic search fallback
// Use when the wiki grows beyond 200 pages and index.md scanning becomes slow
```

Also use Apple-native frameworks (no external dependencies where possible):
- `NaturalLanguage` — `NLContextualEmbedder` for on-device embeddings
- `BackgroundTasks` — for scheduled lint runs
- `Accessibility` — `AXUIElement` APIs
- `ScreenCaptureKit` — modern replacement for CGWindowList (macOS 12.3+)

---

## Claude API integration

Model to use: `claude-sonnet-4-20250514`

API call pattern for all reasoning calls:

```swift
struct ClaudeClient {
    static let endpoint = "https://api.anthropic.com/v1/messages"
    
    func complete(system: String, user: String, maxTokens: Int = 1024) async throws -> String {
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        // Standard URLSession call
        // Parse response.content[0].text
    }
    
    // Vision variant for Electron app screenshots
    func completeWithImage(system: String, user: String, imageBase64: String) async throws -> String {
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": system,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": imageBase64]],
                    ["type": "text", "text": user]
                ]
            ]]
        ]
    }
}
```

Store API key in Keychain, never in UserDefaults or code.

---

## Privacy and permissions

Anna needs these entitlements — implement permission request flows for each:

1. **Accessibility** (`com.apple.security.automation.apple-events`) — required for AXUIElement. Without this, the app is blind. Guide user to System Settings → Privacy & Security → Accessibility on first launch.

2. **Screen Recording** (`com.apple.security.screen-capture`) — required for screenshot fallback (Electron apps). Request only when an Electron app is first detected.

3. **App Sandbox** — keep it sandboxed. All file I/O goes through `~/Library/Application Support/Anna/`. No network calls except to `api.anthropic.com`.

Show a clean permission onboarding flow when the app first runs. Do not request all permissions at once. Request them lazily, explaining why each is needed in plain language when it's first needed.

---

## CLAUDE.md for this project

Create a `CLAUDE.md` file at the root of the project with:

```markdown
# Anna — macOS AI Tutor

## What this is
Anna watches what apps the user is using and teaches them how to use those apps.
It has a self-growing knowledge base that gets smarter with every session.

## Architecture
- PerceptionEngine: reads AXUIElement tree + screenshot fallback
- KnowledgeBase: Karpathy-style three-layer wiki (raw/ → wiki/ → schema.md)
- TutorialEngine: Claude API calls for generating help content  
- LearningLoop: tracks outcomes, updates confidence, triggers lint
- AnnaPanel: SwiftUI floating NSPanel UI

## Key constraints
- Never generate a tip when KB confidence < 40 for that app
- Always check for Electron apps and fall back to screenshot
- API key lives in Keychain only
- All wiki files are plain markdown in ~/Library/Application Support/Anna/
- Lint runs via BackgroundTasks, never blocks UI

## Files to never touch
- schema.md (regenerated by the system, not manually edited)
- raw/ directory (append-only, never delete)

## Testing checklist before any PR
- [ ] Open a native app → accessibility tree reads correctly
- [ ] Open Figma/VS Code → screenshot fallback triggers
- [ ] First launch → onboarding fires within 2 seconds
- [ ] Dismiss a tip → gap gets logged
- [ ] 5 successful sessions → wiki page confidence increases
- [ ] Lint pass → log.md updates
```

---

## Karpathy patterns to specifically implement

These are directly from Andrej Karpathy's LLM Wiki + Agentic Engineering philosophy:

**1. Compile, don't just retrieve.**
RAG retrieves and forgets every query. Anna must compile raw observations into durable wiki pages. The wiki page for Figma should get smarter every session, not restart from zero.

**2. The LLM writes the wiki, not the developer.**
You (Claude Code) should not manually write any app-specific knowledge. The LLM compiles it from real session data. The developer only writes the schema and pipeline. Everything in `wiki/apps/` is LLM-maintained.

**3. The schema file is the most important artifact.**
`schema.md` tells the LLM what kinds of things to write, how to structure them, and what quality bar to hold. Invest time making this file excellent. Everything downstream depends on it.

**4. Linting = test suite for knowledge.**
Run lint weekly. Lint catches staleness, contradictions, and coverage gaps — exactly like a test suite catches regressions. Log all lint runs append-only in `wiki/log.md`.

**5. Confidence scoring prevents hallucination.**
Every app page has a confidence score. Low confidence = no tips = log gaps. This is the core anti-hallucination mechanism. Do not skip it.

**6. Agentic engineering discipline (not vibe coding).**
Every feature must have:
- A clear spec (what it does, what inputs, what outputs)
- An error path (what happens when it fails)
- A logging path (what gets written to disk)

Do not add features without all three.

---

## Improvement priorities (tackle in this order)

1. **Implement PerceptionEngine** — the app is blind without this. Get AXUIElement reading working first. Test on at least: Finder, Safari, Mail, Xcode, Figma.

2. **Implement KnowledgeBase** — file structure, raw/ ingest, wiki/ compilation via Claude API, schema.md generation.

3. **Wire up TutorialEngine** — first-launch onboarding is the most visible feature. Get it working end to end before building tips.

4. **Implement LearningLoop** — confidence scoring, gap logging, dismissal tracking.

5. **Refine the UI** — the panel, hotkey, tip cards, stepper onboarding. Keep it minimal. Every pixel earns its place.

6. **Add lint scheduling** — BackgroundTasks, weekly cadence, log output.

7. **Add VecturaKit** — only after wiki grows beyond 50 pages. Use as search acceleration layer, not replacement for the wiki.

---

## What NOT to do

- Do not use CoreML/CreateML to train local models. Claude API is sufficient and we don't have training data yet.
- Do not build a RAG pipeline with embeddings as the primary system. Follow the Karpathy wiki pattern: compiled markdown first, vector search as scaling optimization later.
- Do not store the wiki in a database. Plain markdown files only. Git-trackable, human-readable, future-proof.
- Do not add onboarding that fires for every app the user already knows. Check session count first.
- Do not show more than one tip at a time. Queue tips, never stack them.
- Do not call the Claude API more than once per screen state change. Debounce with a 3-second minimum interval.
- Do not hardcode any app-specific knowledge. Everything must come from the wiki or real sessions.

---

## Session start checklist (run this before starting work)

```bash
# Verify project compiles
xcodebuild -scheme Anna -configuration Debug build

# Check what exists in the knowledge base dir
ls -la ~/Library/Application\ Support/Anna/ 2>/dev/null || echo "Fresh install"

# Check current wiki state
find ~/Library/Application\ Support/Anna/wiki/ -name "*.md" 2>/dev/null | head -20

# Check schema exists
cat ~/Library/Application\ Support/Anna/schema.md 2>/dev/null || echo "Schema not yet generated"
```

---

## Definition of done for this improvement session

- [ ] PerceptionEngine reads accessibility tree for native apps
- [ ] PerceptionEngine falls back to screenshot for Electron apps  
- [ ] KnowledgeBase creates and maintains `raw/`, `wiki/`, `schema.md`
- [ ] TutorialEngine generates onboarding for a first-launched app
- [ ] Onboarding renders in the Anna panel as a stepper
- [ ] Dismissing a tip logs a gap
- [ ] Following a tip increases app confidence score
- [ ] LearningLoop schedules lint via BackgroundTasks
- [ ] All API keys stored in Keychain
- [ ] Permission flows work: Accessibility + Screen Recording
- [ ] CLAUDE.md is created and accurate
- [ ] Project compiles cleanly with no warnings

Start with item 1. Read every existing file before modifying anything. 
When in doubt, ask — do not assume.
```
