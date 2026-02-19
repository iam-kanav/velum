# Velum - EPUB Reader with Text-to-Speech

Velum is a beautiful, feature-rich EPUB reader for Android and iOS with built-in Text-to-Speech, customizable themes, and a distraction-free reading experience.

---

## Library

- **Import books** manually via file picker or auto-detect EPUBs on your device
- **Search** your library in real time by title or author
- **Sort** by recently read or alphabetically
- **Pin** favourite books to the top of your library
- **Multi-select** books for bulk management (delete, pin/unpin)
- **Reading progress** saved automatically per book (chapter + scroll position)

## Reader

- **WebView-based rendering** with full HTML/CSS support, images, and links
- **Three themes** — Light, Dark, and Sepia — for the reader, independent of the app theme
- **Typography controls** — choose from Serif (Merriweather), Sans-Serif (Inter), Monospace (Roboto Mono), or import your own TTF fonts
- **Adjustable font size** (12–32 px) and **line height** (1.0–2.5)
- **Swipe navigation** — swipe left/right to move between chapters with smooth slide animations
- **Tap to toggle UI** — single tap shows/hides the top and bottom bars; they auto-hide after a few seconds
- **Scroll position persistence** — Velum remembers where you left off in every book

## Global Search

- **Search across all chapters** at once from the reader
- Results appear in a floating popup with match snippets, chapter numbers, and position percentages
- Matched text highlighted in green for easy scanning
- Tap any result to jump directly to that chapter and position
- Search runs off the main thread for smooth performance

## Text-to-Speech

- **Play/Pause** with a floating action button in the reader
- **50+ languages** and multiple voices per language
- **Adjustable speed** (0.2×–2.0×), **pitch**, and **volume**
- **Highlight modes** — sentence-level or paragraph-level visual tracking that follows along as the book is read aloud
- **Double-tap** any paragraph or sentence to jump TTS playback to that point
- **Auto-continue** to the next chapter when the current one finishes
- **Background playback** with media notification controls (play, pause, skip forward/back)
- **Audio focus** — optionally pause when other audio starts playing

## Highlights

- **Select text and highlight** in one of five colours — yellow, green, blue, pink, or orange
- **Highlights panel** shows all your highlights grouped by colour with chapter references
- Tap a highlight to **navigate** directly to it, even across chapters
- Delete individual highlights at any time
- Highlights are **restored automatically** every time a chapter loads

## Settings

- **App theme** (Light, Dark, Sepia) — controls the library and settings UI
- **Reader theme** — independent from the app theme, controls only the reading view
- **Font selection** with live preview, including custom font import
- **Font size and line height sliders** with real-time preview
- **In-reader settings modal** with two tabs — TTS and Reader — accessible without leaving your book
- All settings persist across sessions

## Onboarding

- Guided **four-step onboarding** on first launch:
  1. Welcome and feature overview
  2. Library setup (auto-detect or manual import)
  3. Notification permission for background TTS controls
  4. Theme selection for app and reader

## Book Completion

- A **celebration screen** when you finish the last chapter, with options to go back to the library, start over, or stay on the last page

## Ads

- A small **banner ad** at the bottom of the reader
- **Watch a short rewarded ad** to hide the banner for your entire reading session — a small way to support independent development
- The ad-free session stays active as long as you're using the app or listening to TTS; it resets after 30 minutes of inactivity or when the app is closed
