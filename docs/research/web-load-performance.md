# Web load performance

Checked: 2026-10-21. Sources: Resource Timing API in the Claude desktop browser pane (Chromium), no throttling, against Cloudflare Pages previews. Bean: piano-ndp2.

**Question:** why does the web app sit on a blank navy screen while loading, and what fixes it?

## Findings (before)

`https://feat-practice-mode.easy-piano.pages.dev`, warm CDN, browser cache mostly cold (3 of 142 entries cached).

| Metric | Value |
|---|---|
| Requests | 142 |
| Transferred | 1.51 MB |
| main.dart.js | 808 KB, done at 0.98 s |
| Rust wasm (`pkg/`) | 168 KB, done at 1.70 s |
| Bravura.otf (music font) | 373 KB |
| First content JSON (`index.json`) | 1.82 s |
| Last content JSON (`melody-model-v1.json`) | 7.07 s |
| Content requests | ~125, strictly sequential, ~35 ms each |
| No piano MP3s / samples at boot | they already load on first use |

Two causes:

1. **Splash hid too early.** `index.html` hid the splash 300 ms after `<flutter-view>` appeared. The engine inserts that element at start-up, before `main()` awaits Rust init and content, so users saw ~5 s of empty background.
2. **Content waterfall.** `ContentRepo.load` awaited each of ~125 asset files one after another: ~5.2 s of the ~7.3 s boot.

## Changes

- Splash stays until `flutter-first-frame`; shows "Couldn't load / Reload" on an uncaught error or after 45 s of visible time; warns in the console when not cross-origin isolated.
- `tools/sync_content.py` also writes `assets/content/bundle.json` (all files in one map); `ContentRepo.load` reads it in one request, falling back to parallel per-file loads.
- `main()` runs `RustLib.init`, `AppLocale.load` and `ContentRepo.load` in parallel.
- Bravura.otf (373 KB) left the pubspec font manifest, which web fetches before the first frame. `lib/ui/staff/music_font.dart` loads it with `FontLoader` after the first frame; `StaffPainter` repaints when it lands. Checked on the preview: FontManifest.json no longer lists Bravura, and a lesson staff draws clef and noteheads.

## Results (after)

`https://fix-web-load-speed.easy-piano.pages.dev` (PR #61), same browser and method.

| Metric | Before | After |
|---|---|---|
| Requests | 142 | 16 |
| Transferred | 1.51 MB | 1.36 MB |
| Content | ~125 files, 1.82 to 7.07 s | bundle.json, 20 KB gzip, 1.51 to 1.93 s |
| Last boot resource done | 7.31 s | 2.21 s |
| Screen while waiting | blank navy | branded splash until first frame |

Single run each, unthrottled; not a Lighthouse score.

## Implications

- Boot is now bound by main.dart.js, CanvasKit and the Rust wasm, not content.
- Content stays one bundle until it is large enough to split per course.

## Follow-ups

- Subset Bravura.otf to the glyphs we draw (still 373 KB, now after boot).
- Try skwasm (`flutter build web --wasm`) once COOP/COEP stays on; measure.
- Service worker / PWA caching for repeat visits.
