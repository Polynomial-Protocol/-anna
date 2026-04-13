# Anna TTS Proxy — Cloudflare Worker Setup

A Cloudflare Worker that proxies ElevenLabs API requests so the API key never ships in the app binary.

## Why

- ElevenLabs API key stays server-side (Cloudflare environment variable)
- App only knows the proxy URL — no secrets in the binary
- Free Cloudflare tier handles 100K requests/day
- Adds ~10-20ms latency (negligible vs ElevenLabs ~75ms generation)

## Prerequisites

- Node.js 18+ installed
- Cloudflare account (free at cloudflare.com)
- ElevenLabs paid API key ($5/mo Starter plan minimum — free tier gets blocked by abuse detection)

---

## ElevenLabs Account & API Key Setup

### 1. Create an ElevenLabs Account

Go to [elevenlabs.io](https://elevenlabs.io) and sign up. You need at least the **Starter plan** ($5/mo) — the free tier gets flagged and blocked by their abuse detection system.

### 2. Generate an API Key

1. Go to **elevenlabs.io/app/settings/api-keys**
2. Click **Create API Key**
3. Give it a name (e.g. "Anna TTS Proxy")

### 3. Set API Key Permissions

When creating the key, you'll see three permission toggles. Set them as follows:

| Permission         | Required | What it does                                           |
|--------------------|----------|--------------------------------------------------------|
| **Text to Speech** | Yes      | Converts Anna's text responses to spoken audio (MP3)   |
| **Speech to Speech** | Optional | Voice conversion — transforms one voice into another. Not used by Anna currently, but useful if you want to clone a custom voice later. |
| **Speech to Text** | Optional | Transcription — converts audio to text. Not used by Anna (we use Apple's on-device speech recognition instead). Enable if you plan to use ElevenLabs for transcription in the future. |

**Minimum required:** Toggle **Text to Speech** to "Access". The other two are optional for future features.

### 4. Copy the Key

Copy the key (starts with `sk_`). You'll need it in Step 3 below.

---

## Cloudflare Worker Setup

### Step 1: Create the Worker

```bash
npm create cloudflare@latest anna-tts-proxy
# When prompted:
#   Template: "Hello World" Worker
#   TypeScript: Yes
#   Deploy now: No

cd anna-tts-proxy
```

### Step 2: Replace `src/index.ts`

Delete everything in `src/index.ts` and paste this:

```typescript
export interface Env {
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST",
          "Access-Control-Allow-Headers": "Content-Type, Accept",
        },
      });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const url = new URL(request.url);

    if (url.pathname === "/tts") {
      return handleTTS(request, env);
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID || "pNInz6obpgDQGcFmaJgB";

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "Content-Type": "application/json",
        Accept: "audio/mpeg",
      },
      body,
    }
  );

  return new Response(response.body, {
    status: response.status,
    headers: {
      "Content-Type": "audio/mpeg",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
```

### Step 3: Set Secrets

```bash
# Paste your ElevenLabs API key when prompted (the sk_... key from above)
npx wrangler secret put ELEVENLABS_API_KEY

# Default voice ID (Adam). See voice list below for alternatives.
npx wrangler secret put ELEVENLABS_VOICE_ID
# Paste: pNInz6obpgDQGcFmaJgB
```

### Step 4: Deploy

```bash
npx wrangler deploy
```

You'll get a URL like:
```
https://anna-tts-proxy.<your-subdomain>.workers.dev
```

### Step 5: Test It

```bash
curl -s -o test.mp3 -w "%{http_code}" \
  -X POST "https://anna-tts-proxy.<your-subdomain>.workers.dev/tts" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mpeg" \
  -d '{"text":"Hey, this is Anna speaking.","model_id":"eleven_flash_v2_5","voice_settings":{"stability":0.5,"similarity_boost":0.75}}'

# Should print: 200
# Play it:
afplay test.mp3
```

**If you get 401:** Your API key is wrong, expired, or the account is on the free tier. Double-check the key and ensure you're on a paid plan.

**If you get 400:** The request body is malformed. Make sure Content-Type is `application/json`.

### Step 6: Update Anna

In `Infrastructure/TTS/TTSService.swift`, change the proxy URL:

```swift
private static let elevenLabsProxyURL = "https://anna-tts-proxy.<your-subdomain>.workers.dev/tts"
```

Then rebuild (`xcodegen generate && xcodebuild ...`) and you're done.

---

## ElevenLabs Voice IDs

| Voice    | ID                         | Style                   |
|----------|----------------------------|-------------------------|
| Adam     | `pNInz6obpgDQGcFmaJgB`    | Deep, narrative, steady |
| Drew     | `29vD33N1CtxCmqQRPOHJ`    | Friendly, warm          |
| Emily    | `MF3mGyEYCl7XYWbV9V6O`    | Soft, calm              |
| Chad     | `IKne3meq5aSn9XLyUdCD`    | Confident, energetic    |
| Dorothy  | `ThT5KcBeYPX3keUQqHPh`    | Warm, British           |
| Sarah    | `EXAVITQu4vr4xnSDxMaL`    | Soft, expressive        |
| Gigi     | `jBpfuIE2acCO8z3wKNLl`    | Young, playful          |
| Daniel   | `onwK4e9ZLuTAKqWW03F9`    | Authoritative, British  |

Set `ELEVENLABS_VOICE_ID` to whichever you prefer. The app can also override this per-request if you extend the worker to accept a `voice_id` field in the JSON body.

---

## ElevenLabs API Reference

Anna currently uses only the **Text to Speech** endpoint. Here's a quick reference for all three capabilities in case you want to extend the proxy later.

### Text to Speech (used by Anna)

Converts text to spoken audio. This is what powers Anna's voice.

```
POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}
Header: xi-api-key: <your-key>
Header: Content-Type: application/json
Header: Accept: audio/mpeg

Body:
{
  "text": "Hello from Anna.",
  "model_id": "eleven_flash_v2_5",
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75
  }
}

Response: audio/mpeg binary data
```

**Models:**
| Model               | Latency | Quality | Cost per 1K chars |
|----------------------|---------|---------|--------------------|
| `eleven_flash_v2_5`  | ~75ms   | Good    | $0.15              |
| `eleven_multilingual_v2` | ~200ms | Best | $0.30              |
| `eleven_turbo_v2_5`  | ~50ms   | Good    | $0.15              |

Anna uses `eleven_flash_v2_5` for the best latency/quality balance.

### Speech to Speech (future use)

Transforms audio from one voice to another. Could be used for real-time voice cloning.

```
POST https://api.elevenlabs.io/v1/speech-to-speech/{voice_id}
Header: xi-api-key: <your-key>
Content-Type: multipart/form-data

Form fields:
  audio: <audio file>
  model_id: "eleven_english_sts_v2"
  voice_settings: {"stability": 0.5, "similarity_boost": 0.75}

Response: audio/mpeg binary data
```

**Potential use case:** Let users record their own voice, then have Anna speak in a custom cloned voice.

### Speech to Text (future use)

Transcribes audio to text. Anna currently uses Apple's on-device speech recognition instead.

```
POST https://api.elevenlabs.io/v1/speech-to-text
Header: xi-api-key: <your-key>
Content-Type: multipart/form-data

Form fields:
  audio: <audio file>
  model_id: "scribe_v1"

Response:
{
  "text": "transcribed text here",
  "language_code": "en",
  "words": [...]
}
```

**Potential use case:** Higher accuracy transcription than Apple's built-in, especially for accented speech or noisy environments. Would replace `AppleSpeechTranscriptionService` in Anna.

---

## Costs

| Service            | Free Tier              | Paid                        |
|--------------------|------------------------|-----------------------------|
| Cloudflare Workers | 100K requests/day      | $5/mo for 10M requests      |
| ElevenLabs Starter | —                      | $5/mo = 30K chars (~60 responses) |
| ElevenLabs Creator | —                      | $22/mo = 100K chars (~200 responses) |
| ElevenLabs Pro     | —                      | $99/mo = 500K chars (~1000 responses) |

At ~500 chars per Anna response, the Starter plan covers about 60 voice responses per month.

---

## Optional: Rate Limiting

To prevent abuse if the proxy URL leaks, add to `wrangler.toml`:

```toml
[[unsafe.bindings]]
name = "RATE_LIMITER"
type = "ratelimit"
namespace_id = "1001"
simple = { limit = 100, period = 60 }
```

This caps it at 100 requests per minute.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 401 Unauthorized | Invalid or expired API key | Regenerate key at elevenlabs.io/app/settings/api-keys |
| 401 "unusual activity" | Free tier blocked | Upgrade to a paid plan ($5/mo Starter) |
| 401 "no access" | Key missing TTS permission | Edit key permissions, enable "Text to Speech" |
| 429 Too Many Requests | Rate limited | Wait a minute, or upgrade your ElevenLabs plan |
| 400 Bad Request | Malformed JSON body | Check Content-Type is application/json |
| Worker returns 404 | Wrong URL path | Make sure you're hitting `/tts` not `/` |
