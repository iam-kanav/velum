# Velum

**A beautiful, distraction-free EPUB reader with cloud-powered neural Text-to-Speech, built with Flutter.**

<p align="center">
  <img src="Mockup Screenshots/Light/light_library.png" width="30%" alt="Library – Light" />
  <img src="Mockup Screenshots/Dark/dark_reader.png" width="30%" alt="Reader – Dark" />
  <img src="Mockup Screenshots/Sepia/sepia_tts_settings.png" width="30%" alt="TTS Settings – Sepia" />
</p>

---

## Features at a Glance

- 📚 **Library** — auto-scan your device for EPUBs or import manually, with search, sort, pinning, and per-book reading progress
- 📖 **Reader** — WebView-based rendering with full HTML/CSS support, swipe chapter navigation, and deep typography controls
- 🔊 **Text-to-Speech** — your phone's own speech engine (Edge neural voices optional) with synced sentence/paragraph highlighting and lock-screen controls
- 🖍️ **Highlights & Bookmarks** — five highlight colours plus positional bookmarks, browsable from a single panel
- 🔍 **Global Search** — search every chapter at once with snippet previews
- 🎨 **Theming** — Light, Dark, and Sepia, applied independently to the app UI and the reading view

---

## Text-to-Speech Engine

Velum reads aloud with the **speech engine installed on your phone** (via [`flutter_tts`](https://pub.dev/packages/flutter_tts)) — e.g. Speech Services by Google or Samsung TTS. It works offline and starts speaking almost instantly. On Android you can pick any installed engine and any of its downloaded voices.

**Microsoft Edge neural voices** (via [`edge_tts`](https://pub.dev/packages/edge_tts)) are still available as an **experimental** option in the TTS settings. They sound more natural but need an internet connection and take longer to start.

### How playback works

1. **One source of truth** — when a chapter is rendered, each paragraph is split into sentence spans and the same pass records the spoken text for each span, so the voice and the highlight always point at the same sentence.
2. **Chunking** — chapter text is spoken sentence by sentence or paragraph by paragraph (matching the highlight mode).
3. **Device engine** — each chunk is handed straight to the phone's engine; pausing stops the current sentence and resuming restarts it.
4. **Edge engine (experimental)** — chunks are synthesized to MP3 in the background (3 at a time, starting from the reading position), kept in a 40-entry LRU cache, and played with [`just_audio`](https://pub.dev/packages/just_audio).
5. **System integration** — [`audio_service`](https://pub.dev/packages/audio_service) (`VelumAudioHandler`) provides lock-screen / notification controls, and [`audio_session`](https://pub.dev/packages/audio_session) handles interruptions from other apps.

### TTS features

- Play/Pause floating button in the reader with a synthesis progress indicator
- Choose the speech engine and voice, with one-tap voice preview
- Adjustable speed (0.2×–2.0×), pitch, and volume
- **Sentence-level or paragraph-level highlighting** that auto-scrolls to follow along
- Press Play to start from the first sentence on screen; double-tap any paragraph or sentence to jump playback to that point
- Scroll away while listening and the page stops following the voice; tap **Back to reading** to return
- **Sleep timer** — stop after 15, 30 or 60 minutes, or at the end of the chapter
- Auto-advance to the next chapter when the current one finishes
- Optionally stop when another app takes audio focus
- Book and chapter shown on the lock screen and in the media notification

<p align="center">
  <img src="Mockup Screenshots/Light/light_tts_settings.png" width="28%" alt="TTS Settings – Light" />
  <img src="Mockup Screenshots/Dark/dark_tts_settings.png" width="28%" alt="TTS Settings – Dark" />
  <img src="Mockup Screenshots/Sepia/sepia_tts_settings.png" width="28%" alt="TTS Settings – Sepia" />
</p>

---

## Library

<p align="center">
  <img src="Mockup Screenshots/Light/light_library.png" width="28%" alt="Library – Light" />
  <img src="Mockup Screenshots/Dark/dark_library.png" width="28%" alt="Library – Dark" />
  <img src="Mockup Screenshots/Sepia/sepia_library.png" width="28%" alt="Library – Sepia" />
</p>

- Auto-detect all EPUB files on your device, or import them manually via file picker
- Metadata and cover extraction run in a background isolate, stored in a **Hive** database
- Search your library in real time by title or author
- Sort by recently read or alphabetically; pin favourites to the top
- Multi-select for bulk delete or pin/unpin
- Reading progress (chapter + scroll position) saved automatically per book

---

## Reader

<p align="center">
  <img src="Mockup Screenshots/Light/light_reader.png" width="28%" alt="Reader – Light" />
  <img src="Mockup Screenshots/Dark/dark_reader.png" width="28%" alt="Reader – Dark" />
  <img src="Mockup Screenshots/Sepia/sepia_reader.png" width="28%" alt="Reader – Sepia" />
</p>

- Full HTML/CSS rendering in a WebView, with image and external-link support
- EPUB parsing (via `epubx`) offloaded to a background isolate — no UI jank on large books
- Swipe left/right to move between chapters with smooth slide animations
- Tap anywhere to show/hide the UI — bars auto-hide after a few seconds
- Table of Contents modal for jumping straight to any chapter
- Select text and highlight in **five colours** (yellow, green, blue, pink, orange)
- **Bookmarks** — save your exact position and jump back to it from the combined Highlights & Bookmarks panel
- Global search across all chapters with snippet previews and chapter/position info
- Scroll position restored exactly where you left off
- First-launch reader tutorial and a celebration screen when you finish a book

---

## Settings & Customization

<p align="center">
  <img src="Mockup Screenshots/Light/light_reader_settings.png" width="28%" alt="Reader Settings – Light" />
  <img src="Mockup Screenshots/Dark/darj_reader_settings.png" width="28%" alt="Reader Settings – Dark" />
  <img src="Mockup Screenshots/Sepia/sepia_reader_settings.png" width="28%" alt="Reader Settings – Sepia" />
</p>

- Independent **app theme** and **reader theme** (Light / Dark / Sepia)
- Font selection: Serif (Merriweather), Sans-Serif (Inter), Monospace (Roboto Mono), or **import your own TTF**
- Font size (12–32 px), line height (1.0–2.5), and paragraph spacing with live preview
- Horizontal margins (0–40 px) and text alignment (left / justified)
- In-reader settings modal (TTS + Reader tabs) — no need to leave your book
- All settings persist across sessions
- Guided onboarding on first launch: library setup, notification permission for TTS controls, and theme selection

---

## Tech Stack

| Concern | Solution |
|---|---|
| Framework | Flutter (Dart SDK ^3.8.1) |
| State management | `provider` (ChangeNotifier) |
| Navigation | `go_router` with an onboarding redirect guard |
| EPUB parsing | `epubx`, run in background isolates |
| Content rendering | `webview_flutter` + injected `assets/js/reader.js` (gestures, highlights, TTS sync) |
| Text-to-Speech | `flutter_tts` (device engines); `edge_tts` (experimental) |
| Audio playback | `just_audio` + `audio_service` + `audio_session` |
| Library storage | `hive` (with automatic migration from SharedPreferences) |
| Settings / highlights / bookmarks | `shared_preferences` |
| Monetization | `google_mobile_ads` (banner in the reader; rewarded ad grants an ad-free session) |

## Project Structure

The codebase follows a feature-first layout, with each feature split into `data` (models + services) and `presentation` (providers + UI) layers:

```
lib/
├── main.dart                    # Bootstrap: ads, Hive, audio_service, DI via MultiProvider
├── core/
│   ├── providers/               # AdNotifier (ad-free session state)
│   ├── router/                  # go_router config + onboarding redirect
│   ├── services/                # AdService (AdMob)
│   ├── theme/                   # App-wide themes and colors
│   └── widgets/                 # BannerAdWidget
└── features/
    ├── library/
    │   ├── data/                # ScannedBook (Hive model), LibraryService (scan/import/progress)
    │   └── presentation/        # LibraryNotifier, LibraryScreen
    ├── onboarding/
    │   └── presentation/        # First-launch onboarding flow
    ├── reader/
    │   ├── data/                # EpubService (isolate parsing), Highlight & Bookmark models/services
    │   └── presentation/        # ReaderNotifier, ReaderScreen (WebView), modals & overlays
    ├── settings/
    │   ├── data/                # ReaderSettings, CustomFont
    │   └── presentation/        # SettingsNotifier, settings screen & in-reader modal
    └── tts/
        ├── data/                # TtsSettings, TtsService (Edge TTS + just_audio), VelumAudioHandler
        └── presentation/        # TtsNotifier, TTS FAB, TTS settings UI

assets/js/reader.js              # Injected WebView script: swipe/tap gestures, highlight
                                 # rendering, double-tap-to-speak, TTS highlight sync
```

## Getting Started

```bash
flutter pub get
flutter run
```

Hive type adapters (`*.g.dart`) are committed; regenerate them after model changes with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

> **Note:** TTS requires an internet connection — audio is synthesized by Microsoft's Edge TTS cloud service, not an on-device engine.
