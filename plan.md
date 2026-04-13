# Anna — Detailed Implementation Plan

## Table of Contents
1. [ElevenLabs TTS Integration](#1-elevenlabs-tts-integration)
2. [Memory + Long Context System](#2-memory--long-context-system)
3. [Pointer & Guided Tour Improvements](#3-pointer--guided-tour-improvements)
4. [Timeline & Dependencies](#4-timeline--dependencies)

---

## 1. ElevenLabs TTS Integration

### Why
Gautham: "The sound is sort of garbage." Current Piper/Apple TTS sounds mechanical. ElevenLabs Flash v2.5 produces natural, human-quality speech at ~75ms latency.

### Architecture (Matching Clicky)

```
Anna App (Swift)
  └─ ElevenLabsTTSService (actor)
       └─ URLSession POST → Cloudflare Worker proxy
                                └─ ElevenLabs API (api.elevenlabs.io)
                                     └─ Returns MP3 audio stream
```

**Security model:** API key NEVER in the app binary. Stored in Cloudflare Worker environment variables. App only knows the proxy URL.

### API Details

| Field | Value |
|-------|-------|
| Endpoint | `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}` |
| Auth | `xi-api-key` header (on proxy, not client) |
| Model | `eleven_flash_v2_5` (~75ms latency, best for real-time) |
| Response | `audio/mpeg` binary MP3 data |
| Stability | `0.5` (natural emotion + consistency) |
| Similarity | `0.75` (strong voice match) |

### Request Format
```json
{
  "text": "Your text here",
  "model_id": "eleven_flash_v2_5",
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75
  }
}
```

### Pricing

| Model | Cost per 1K chars | 100-word response (~500 chars) |
|-------|-------------------|-------------------------------|
| Flash v2.5 | $0.30 | ~$0.00015 |
| Multilingual v2 | $0.60 | ~$0.00030 |
| Free tier | 10K chars/month | ~20 responses |

### Implementation Steps

#### Step 1: Cloudflare Worker Proxy
Create a simple worker with `/tts` endpoint that:
- Receives text + settings from Anna
- Adds API key from `env.ELEVENLABS_API_KEY`
- Adds voice ID from `env.ELEVENLABS_VOICE_ID`
- Forwards to ElevenLabs API
- Streams audio response back to Anna

```typescript
// worker/src/index.ts
async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${env.ELEVENLABS_VOICE_ID}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );
  return new Response(response.body, {
    status: response.status,
    headers: { "content-type": "audio/mpeg" },
  });
}
```

#### Step 2: Swift TTS Service (Actor)
New file: `Infrastructure/TTS/ElevenLabsTTSService.swift`

```swift
@MainActor
final class ElevenLabsTTSService {
    private let proxyURL: URL
    private let session: URLSession
    private var audioPlayer: AVAudioPlayer?

    init(proxyURL: String) {
        self.proxyURL = URL(string: proxyURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func speakText(_ text: String) async throws {
        stopPlayback()

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TTSError.apiError(String(data: data, encoding: .utf8) ?? "Unknown")
        }

        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.play()
    }

    var isPlaying: Bool { audioPlayer?.isPlaying ?? false }
    func stopPlayback() { audioPlayer?.stop(); audioPlayer = nil }
}
```

#### Step 3: Integration with Existing TTSService
- Add ElevenLabs as primary TTS engine
- Fall back to current Piper/Apple TTS if ElevenLabs fails
- Settings UI: proxy URL field, test button, toggle between ElevenLabs/Apple

#### Step 4: Interruption Handling
- When user speaks again: `ttsService.stopPlayback()` + cancel current task
- `Task.checkCancellation()` after every await point
- Instant responsiveness (~50-100ms interruption latency)

#### Step 5: Settings UI
- New "Voice" section: ElevenLabs proxy URL, voice selection
- Test voice button
- Character count display (for cost awareness)
- Toggle: ElevenLabs / Apple TTS / Piper

### Voice Recommendations

| Voice | Character | Best For |
|-------|-----------|----------|
| Drew | Steady, friendly | General assistant (recommended) |
| Emily | Soft, calm | Patient guidance |
| Chad | Confident, energetic | Authoritative responses |
| Dorothy | Warm, British | Sophisticated/trust |

### Files to Create/Modify
- **NEW:** `Infrastructure/TTS/ElevenLabsTTSService.swift`
- **NEW:** `worker/` directory with Cloudflare Worker
- **MODIFY:** `Infrastructure/TTS/TTSService.swift` — add ElevenLabs as primary engine
- **MODIFY:** `Features/Settings/SettingsView.swift` — ElevenLabs settings section
- **MODIFY:** `Models/AssistantModels.swift` — add proxy URL to AppSettings

---

## 2. Memory + Long Context System

### Why
Gautham: "Memory is gonna be the big difference." Current KnowledgeStore uses FTS5 keyword search only — no semantic understanding, no memory types, no consolidation. Products like Limitless.ai and Rewind.ai show memory is a key differentiator.

### Current State (KnowledgeStore.swift)
- SQLite database at `~/Library/Application Support/Anna/knowledge/knowledge.db`
- FTS5 full-text search (keyword matching only)
- 5 sources: clipboard, conversation, note, URL, screenshot
- No embeddings, no vector search, no memory types
- No staleness handling, no retention policies

### Target Architecture

```
┌─────────────────────────────────────────────────┐
│ SQLite Database (single file, local-only)        │
├─────────────────────────────────────────────────┤
│ entries          — Core data (existing)           │
│ entries_fts      — FTS5 keyword index (existing)  │
│ embeddings       — Vector embeddings (NEW)        │
│ embeddings_vec   — sqlite-vec KNN index (NEW)     │
│ entry_relations  — Memory graph links (NEW)       │
│ repetition_sched — Spaced repetition (NEW)        │
│ consolidation_log — Audit trail (NEW)             │
└─────────────────────────────────────────────────┘
```

### Phase 1: Vector Search (Week 1-2)

#### 1a. Add sqlite-vec Extension
- Pure C, zero dependencies, <5MB
- K-Nearest Neighbor search with SIMD acceleration
- Swift bindings: https://github.com/jkrukowski/SQLiteVec
- Supports cosine, euclidean, dot product distance

#### 1b. Embedding Generation with Apple NLEmbedding
- Built-in macOS framework (NaturalLanguage)
- 512-dimensional sentence embeddings
- Zero external dependencies, 100% local, free
- ~500ms per 1KB of text

```swift
import NaturalLanguage

actor EmbeddingService {
    private let model = NLEmbedding.sentenceEmbedding(for: .english)

    func embed(_ text: String) -> [Float]? {
        model?.vector(for: text)?.map { Float($0) }
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).map(*).reduce(0, +)
        let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}
```

#### 1c. Schema Migration

```sql
-- Add metadata to entries
ALTER TABLE entries ADD COLUMN memory_type TEXT DEFAULT 'episodic';
ALTER TABLE entries ADD COLUMN consolidation_status TEXT DEFAULT 'new';
ALTER TABLE entries ADD COLUMN last_accessed REAL;
ALTER TABLE entries ADD COLUMN access_count INTEGER DEFAULT 0;

-- Vector embeddings
CREATE TABLE embeddings (
    id INTEGER PRIMARY KEY,
    entry_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    embedding_model TEXT NOT NULL,
    dimension INTEGER DEFAULT 512,
    created_at REAL NOT NULL,
    FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE
);

-- sqlite-vec virtual table
CREATE VIRTUAL TABLE embeddings_vec USING vec0(
    embedding(dimension=512)
);
```

#### 1d. Hybrid Search (FTS5 + Vector)

```swift
func hybridSearch(query: String, limit: Int = 10) -> [KnowledgeEntry] {
    let vectorResults = vectorSearch(query, limit: limit * 2)  // 90% weight
    let ftsResults = ftsSearch(query, limit: limit * 2)        // 10% weight

    // Merge by combined score
    var scores: [Int64: Double] = [:]
    for (i, r) in vectorResults.enumerated() {
        scores[r.id, default: 0] += (1.0 - Double(i) / Double(limit)) * 0.9
    }
    for (i, r) in ftsResults.enumerated() {
        scores[r.id, default: 0] += (1.0 - Double(i) / Double(limit)) * 0.1
    }
    return topK(scores, limit: limit)
}
```

#### 1e. Background Batch Embedding
- Process 50 entries every 30 seconds in background
- Don't block UI — use `Task.detached` with `.background` priority
- Embed new entries as they arrive
- Gradually index existing entries over time

### Phase 2: Memory Types & Consolidation (Week 3-4)

#### Memory Types (inspired by Limitless.ai)

| Type | Description | Decay |
|------|-------------|-------|
| `episodic` | Raw conversations, events | 30 days |
| `semantic` | Distilled facts, patterns | 18 months |
| `procedural` | How-to knowledge, routines | Never |
| `contextual` | Current session state | End of session |
| `permanent` | User-pinned memories | Never |

#### Memory Consolidation Pipeline
Run periodically (e.g., daily or on 100+ new entries):

1. **Extract patterns** — Group similar episodic memories, use Claude to summarize into semantic facts
2. **Deduplicate** — Vector similarity >0.92 = likely duplicate, merge
3. **Link related** — Build relationship graph between entries
4. **Archive stale** — Move low-access entries older than 30 days to archived state
5. **Update repetition** — Spaced repetition (SM-2 algorithm) for important facts

#### Staleness Handling
- Facts older than 18 months: flag `needs_confirmation = true`
- UI prompt: "You mentioned wanting to learn Python 18 months ago. Still interested?"
- User confirms → reset timer. User dismisses → archive.

### Phase 3: Privacy & Optimization (Week 5-6)

#### Encryption at Rest
- AES-256-GCM for the database file
- Key stored in macOS Keychain
- Optional — toggled in Settings

#### Data Retention Policies

| Policy | Behavior |
|--------|----------|
| `permanent` | Never delete |
| `6_months` | Auto-delete after 6 months |
| `1_year` | Auto-delete after 1 year |
| `until_expired` | Delete at `expires_at` date |
| `user_only` | User manually deletes |

#### Performance Targets

| Metric | Target |
|--------|--------|
| Vector search | <100ms on 10K vectors |
| Embedding generation | <500ms per 1KB text |
| FTS5 keyword search | <50ms on 50K entries |
| Hybrid search | <150ms combined |
| Memory footprint | <500MB for 50K vectors @ 512-dim |

### Files to Create/Modify
- **NEW:** `Infrastructure/Knowledge/EmbeddingService.swift`
- **NEW:** `Infrastructure/Knowledge/SemanticSearchEngine.swift`
- **NEW:** `Infrastructure/Knowledge/MemoryConsolidationPipeline.swift`
- **NEW:** `Infrastructure/Knowledge/SpacedRepetitionScheduler.swift`
- **NEW:** `Models/MemoryModels.swift` — memory types, consolidation states
- **MODIFY:** `Infrastructure/Knowledge/KnowledgeStore.swift` — add vector search, hybrid search
- **MODIFY:** `Infrastructure/Persistence/ConversationStore.swift` — SQLite persistence (currently in-memory only, 100 turns max)
- **MODIFY:** `Infrastructure/Persistence/MigrationManager.swift` — schema migration
- **MODIFY:** `Domain/AssistantEngine.swift` — use hybrid search for context injection
- **MODIFY:** Settings UI — memory analytics, retention policies, encryption toggle

### Dependencies
- `sqlite-vec` — SPM package for vector search (https://github.com/jkrukowski/SQLiteVec)
- No other new dependencies (NLEmbedding is built-in)

---

## 3. Pointer & Guided Tour Improvements

### Why
Gautham: "Why did the pointer go away after you clicked?" + the guided tour needs to be more polished for B2B onboarding.

### 3a. Pointer Behavior After Click

**Current:** Pointer hides 1s after click.
**Fix:** Keep pointer visible, transition to idle-following mode after brief dwell.

**Implementation:**
```swift
// In handlePointerAndSpeak, after click:
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    // Instead of hiding, fly back to cursor and resume following
    self.pointerOverlayManager.returnToCursor()
}
```

- After click ripple plays, buddy flies back to mouse cursor (Bezier arc return)
- Resumes following cursor in idle mode
- Only fully hides when status returns to `.idle` AND no tour is active

### 3b. Tour Progress Indicator

**Current:** No progress visibility.
**Fix:** Show "Step 2 of 5" in the status line.

```swift
// In continueGuidedWalkthrough:
self.statusLine = "Showing you around... step \(guidedModeStepCount + 1)"
```

### 3c. Tour Analytics

Track these events for B2B reporting:

| Event | Properties | Why |
|-------|------------|-----|
| `tour_started` | tourGuideId, tourName, timestamp | Adoption |
| `tour_step_shown` | stepIndex, elementLabel, timestamp | Engagement |
| `tour_step_clicked` | stepIndex, clickTarget, durationMs | Interaction |
| `tour_abandoned` | stepIndex, reason, totalDurationMs | Drop-off |
| `tour_completed` | totalSteps, totalDurationMs | Success |

**Implementation:** Add a `TourAnalytics` struct that logs to RuntimeLogger (for now) and can be swapped to PostHog/Mixpanel later.

### 3d. Skip/Pause Controls

During a tour, show controls in the status bar:
- **"Stop"** button — cancels tour, resets state
- Step counter — "Step 2 of 5"

**Implementation:** Already have a Stop button for TTS. Extend it for tour mode:
```swift
if isInTourMode {
    Button("Stop Tour") {
        guidedModeStepCount = 0
        isInTourMode = false
        status = .idle
    }
}
```

### 3e. Conditional Error Recovery

If a click doesn't change the UI (screenshot looks the same):
- Detect: compare screenshot hashes before/after click
- Recovery: "Hmm, that click didn't seem to work. Let me try again." + retry with slightly adjusted coordinates
- Max 1 retry, then skip to next step

### 3f. B2B Positioning

Anna's guided tour system is unique in the market:

| Competitor | Approach | Price | Anna's Advantage |
|-----------|----------|-------|-----------------|
| Pendo | Modal overlays, no voice | $15K+/yr | Voice + pointer feels personal |
| WalkMe | Enterprise, complex setup | $50K+/yr | Simple .txt knowledge base |
| Intercom | Chat-only tours | $74/mo+ | Visual pointer + actual clicks |
| Chameleon | Code-based, tooltips | $279/mo+ | AI-generated, no code needed |

**Anna's unique value:** Voice-guided + visual pointer + actual clicks + AI-generated from a text file. No code integration needed.

### Files to Modify
- **MODIFY:** `UIComponents/PointerOverlayView.swift` — pointer return-to-cursor after click
- **MODIFY:** `Features/Assistant/AssistantViewModel.swift` — progress indicator, skip controls, analytics logging
- **NEW:** `Infrastructure/Analytics/TourAnalytics.swift` — event tracking

---

## 4. Timeline & Dependencies

### Dependency Chain
```
ElevenLabs TTS ──────────────── (independent, can start immediately)
Memory System Phase 1 ────────── (independent, can start in parallel)
Memory System Phase 2 ────────── (depends on Phase 1)
Memory System Phase 3 ────────── (depends on Phase 2)
Pointer Improvements ─────────── (independent, quick wins)
Tour Analytics ───────────────── (independent, quick win)
```

### Recommended Order

| Week | Task | Effort |
|------|------|--------|
| **Week 1** | ElevenLabs TTS (Cloudflare Worker + Swift service) | 3 days |
| **Week 1** | Pointer improvements (don't hide, progress indicator) | 1 day |
| **Week 2** | Memory Phase 1 (sqlite-vec, NLEmbedding, hybrid search) | 5 days |
| **Week 3** | Memory Phase 1 cont. (batch embedding, migration) | 3 days |
| **Week 3** | Tour analytics + skip controls | 2 days |
| **Week 4** | Memory Phase 2 (types, consolidation, staleness) | 5 days |
| **Week 5** | Memory Phase 2 cont. (relationship graph, UI) | 3 days |
| **Week 5** | Polish + testing | 2 days |
| **Week 6** | Memory Phase 3 (encryption, retention, privacy) | 5 days |

### Quick Wins (can ship this week)
1. Pointer doesn't hide after click (30 min)
2. Tour progress indicator "Step X of Y" (15 min)
3. Stop Tour button (15 min)

### What to Ship First
1. **ElevenLabs TTS** — immediate quality improvement users will notice
2. **Pointer fixes** — small effort, big polish
3. **Memory Phase 1** — the "big difference" feature

---

## Appendix: Research Sources

### ElevenLabs
- Clicky's implementation: `/tmp/clicky/leanring-buddy/ElevenLabsTTSClient.swift`
- API docs: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- Models: https://elevenlabs.io/docs/overview/models
- Pricing: https://elevenlabs.io/pricing

### Memory Systems
- sqlite-vec: https://github.com/asg017/sqlite-vec
- Apple NLEmbedding: https://developer.apple.com/documentation/naturallanguage/nlembedding
- VecturaKit: https://github.com/rryam/VecturaKit
- Limitless AI: https://limitless.ai/developers
- Screenpipe: https://github.com/screenpipe/screenpipe

### Guided Tours (B2B)
- Pendo: https://www.pendo.io
- WalkMe: https://www.walkme.com
- Chameleon: https://www.chameleon.io
- Product tour metrics: https://productfruits.com/blog/product-tour-metrics
- B2B onboarding: https://productled.com/blog/5-best-practices-for-better-saas-user-onboarding
