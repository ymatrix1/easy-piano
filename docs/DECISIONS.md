# Decisions

Each decision records **Context, Decision, Why, Alternatives, Impact**, plus **Status** (`proposed`, `accepted`, `superseded`, `rejected`) and **Decided by** once decided. Only the user accepts or rejects. Accepted decisions are frozen; a change is a new decision that supersedes the old one.

## Index

| # | Date | Decision | Status |
|---|---|---|---|
| [D1](#d1-flutter-for-ui-on-all-targets) | 2026-10-15 | Flutter for UI on all targets | accepted |
| [D2](#d2-rust-core-for-music-logic-and-audio) | 2026-10-15 | Rust core for music logic and audio | accepted |
| [D3](#d3-own-json--text-notation-content-format) | 2026-10-15 | Own JSON + text-notation content format | accepted |
| [D4](#d4-no-video-animation-scenes-instead) | 2026-10-15 | No video: animation scenes instead | accepted |
| [D5](#d5-midi-first-microphone-second) | 2026-10-15 | MIDI first, microphone second | accepted |
| [D6](#d6-clean-room-content) | 2026-10-15 | Clean-room content | accepted |
| [D7](#d7-beans-for-task-tracking) | 2026-10-15 | beans for task tracking | accepted |
| [D8](#d8-local-first-no-account-required) | 2026-10-15 | Local-first, no account required | accepted |
| [D9](#d9-web-is-the-first-release-target) | 2026-10-15 | Web is the first release target | accepted |
| [D10](#d10-ui-stack-material-3-themed-riverpod-go_router) | 2026-10-15 | UI stack: Material 3 themed, Riverpod, go_router | accepted |
| [D11](#d11-personal-song-import-with-level-based-simplification) | 2026-10-16 | Personal song import with level-based simplification | accepted |
| [D12](#d12-skill-backbone-with-profile-variants) | 2026-10-16 | Skill backbone with profile variants (audience, taste, locale) | accepted |
| [D13](#d13-one-polished-arena-style-theme-main-menu-with-nav-bar-and-two-level-course-trail) | 2026-10-16 | One polished arena-style theme, main menu, two-level course trail | proposed |

## Accepted

### D1. Flutter for UI on all targets

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Need Android, iOS, web (and desktop) from one codebase with 60 fps scrolling notation.
- **Decision:** Flutter (Impeller on mobile, CanvasKit/skwasm on web). Practice studio drawn with `CustomPainter`; app shell with widgets.
- **Why:** Own renderer = identical pixels on every target; mature `CustomPainter`/`Ticker`; good wasm web build; one language for UI.
- **Alternatives:** React Native + Skia (bridge jank risk, weaker web canvas story); Kotlin Multiplatform + Compose (web canvas still young); web-only PWA in TS (no reliable iOS MIDI, background audio limits); LibGDX like Simply Piano (Java, weak web/iOS today); Godot (heavy, poor app-shell UX).
- **Impact:** Contributors need Dart. Revisit if Flutter web audio/MIDI interop proves unworkable in the Phase 0 spike.

### D2. Rust core for music logic and audio

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Grading and timing must be deterministic, testable and shared; audio must avoid GC pauses.
- **Decision:** Rust crates `core` (pure logic) and `audio` (I/O, synth, pitch), bound to Dart via `flutter_rust_bridge` (FFI native, wasm web).
- **Why:** One implementation of notation parsing, grading and clock for every target; real-time safe; strong test tooling.
- **Alternatives:** All Dart (simplest; GC risk in audio path, but fine for pure logic: fallback if FRB web is painful); C++/JUCE (licensing, harder contributor onboarding).
- **Impact:** Two toolchains in CI. Phase 0 spike must prove FRB on web + Android + iOS. If it fails, keep `core` logic in Dart and only audio native.

### D3. Own JSON + text-notation content format

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Lessons must be hand-authorable, diffable in PRs, and validated.
- **Decision:** JSON files for structure (course, journey, level, stage, scene) with a compact note text notation (inspired by Simply Piano's `C4:1/4%1` style, own grammar). MusicXML and MIDI supported only as **import** sources via CLI.
- **Why:** MusicXML is verbose and painful to review; text notation is one line per phrase and carries fingering and hand.
- **Alternatives:** MusicXML as source of truth (verbose, layout noise); MIDI (no fingering/notation semantics); ABC notation (close, but weak two-hand and fingering support; reconsider as an extension).
- **Impact:** Need a parser + JSON Schema + linter. Spec: [content-format](specs/content-format.md).

### D4. No video: animation scenes instead

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Simply Piano uses ~377 CDN videos. Videos are heavy, unlocalizable, uneditable, copyrighted.
- **Decision:** Every teaching moment is an `animation` stage: a declarative timeline (keyboard highlights, hand/finger model, staff, captions, voice-over optional, synth audio) rendered by the app.
- **Why:** KB-sized, localizable via string tables, tempo-scalable, mirror-able for left-handed, fully open, editable in PR.
- **Alternatives:** Re-record our own videos (cost, same downsides); Lottie files (designer-made, not data-aware, hard to sync to notes); Rive (good for character/mascot moments: allowed inside scenes as optional asset).
- **Impact:** Need scene DSL, scene player, hand model. Reference videos are understood via `agy` (Google Antigravity CLI) to produce scene briefs. Spec: [animations](specs/animations.md).

### D5. MIDI first, microphone second

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Polyphonic mic recognition needed an ML model and echo cancellation in Simply Piano.
- **Decision:** v1 ships MIDI + on-screen touch keyboard. Mic monophonic (YIN) in Phase 3; score-informed polyphonic detection is a research track.
- **Why:** MIDI is exact and cheap; lets us validate the curriculum early.
- **Alternatives:** Mic first (most users have acoustic or no-MIDI keyboards; but high risk to block everything on ML).
- **Impact:** Early audience skews to MIDI keyboard owners. Timing windows differ per input ([exercise engine](specs/exercise-engine.md)).

### D6. Clean-room content

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** We reverse-engineer Simply Piano for structure and pedagogy. Its levels, songs, audio, art and videos are copyrighted.
- **Decision:** Never commit files, text, melodies-as-arranged, images or audio from the reference APK or its CDN. Use it only to learn structure, sequencing and mechanics. All content is original or public domain, arranged by us, licensed CC-BY-SA-4.0. `references/` is git-ignored.
- **Why:** Legal safety; open license must be clean.
- **Alternatives:** Import their content (illegal); ignore the reference (lose proven pedagogy).
- **Impact:** Agents must follow `.agents/rules/content-and-licensing.md`. Public-domain song choice is ours (Ode to Joy, Jingle Bells, Twinkle Twinkle, Minuet in G, etc.).

### D7. beans for task tracking

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Need agent-friendly tasks that live with the code, as in the vantage project.
- **Decision:** [hmans/beans](https://github.com/hmans/beans), config `.beans.yml`, prefix `piano-`, files in `.beans/`.
- **Why:** Markdown in git, CLI for agents, dependencies and epics, worked well in vantage.
- **Alternatives:** GitHub Issues (not offline, not in PR diff); TODO.md (no structure).
- **Impact:** Every PR closes its bean(s). Rules in `AGENTS.md`.

### D8. Local-first, no account required

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** Open-source app; privacy; offline practice.
- **Decision:** Progress stored locally in SQLite via `drift`: native SQLite on mobile/desktop, sqlite3 wasm on web (OPFS, IndexedDB fallback). Request `navigator.storage.persist()`; offer progress export/import file. Accounts/sync optional, later.
- **Why:** No backend cost, no personal data, works offline.
- **Alternatives:** Supabase/Firebase from day one (cost, privacy, lock-in).
- **Impact:** Sync design deferred ([OQ5](OPEN-QUESTIONS.md)).

### D9. Web is the first release target

- **Status:** accepted 2026-10-15
- **Decided by:** Yuri Olive
- **Context:** User wants the first version to run in the browser: zero install, easiest to share and test.
- **Decision:** Phase 1 ships web only (Chrome/Edge/Firefox with Web MIDI; Safari via touch, mic later). Mobile builds compile in CI but release in Phase 2. Same Flutter codebase (D1).
- **Why:** Fastest feedback loop; no store review; Web MIDI is exact on desktop browsers where most MIDI-keyboard learners sit.
- **Alternatives:** Mobile first (stores, native latency; slower iteration). TS web app + Capacitor (smaller first load, but weaker mobile MIDI/latency later; would supersede D1).
- **Impact:** Phase 0 spike must measure Flutter web first-load size and Web MIDI latency. If first load > 5 MB or latency > 30 ms p95, revisit D1. Hosting needs COOP/COEP headers.

### D10. UI stack: Material 3 themed, Riverpod, go_router

- **Status:** accepted 2026-10-16
- **Decided by:** Yuri Olive
- **Context:** Need app-shell widgets, state and routing for Flutter (D1), web first (D9), with a playful game look.
- **Decision:** Material 3 widgets with a custom theme and `ThemeExtension` tokens; own `CustomPainter`s for staff, keyboard, falling notes and scenes; `flutter_animate` for motion, Rive for mascot/celebrations; Riverpod for state; go_router for URL routing; Material Symbols, a rounded OFL font, Bravura for music glyphs.
- **Why:** Built in, accessible, cross-platform; theming removes the stock look; Riverpod is testable; go_router gives web deep links.
- **Alternatives:** shadcn_flutter / forui (SaaS look); Cupertino (iOS only); Flame (game engine, overkill for shell); Bloc (more boilerplate).
- **Impact:** All screens use theme tokens, no hard-coded colors. Revisit if Material theming can't reach the target look.

### D11. Personal song import with level-based simplification

- **Status:** accepted 2026-10-16
- **Decided by:** Yuri Olive
- **Context:** Users want to learn any song they like at their level, e.g. a song they hear on YouTube, with simplified versions generated for them.
- **Decision:** Add a "My songs" import: the user supplies their own audio file, MIDI or MusicXML. Audio is first split into stems on device (Demucs class model, MIT: vocals, drums, bass, piano, other); the piano or vocal-melody stem is transcribed (Basic Pitch class model, ONNX/wasm), then a deterministic arranger in Rust `core` produces level variants (beginner: RH melody in C within a 5-finger position; intermediate: melody + LH roots; advanced: chords/styles). The remaining stems become the play-along backing track (user can mute any stem, e.g. remove vocals or the piano part they play). Results stay on the device, for personal use; never uploaded to or shared through our catalog. No YouTube or other site downloader.
- **Why:** Big motivation boost (learn the song you want); keeps the app legal: downloading from YouTube breaks its terms, and copyrighted songs can't be distributed with an open catalog.
- **Alternatives:** YouTube URL downloader (ToS violation, legal risk, store rejection); server-side transcription (cost, uploads copyrighted audio, privacy); LLM-only arrangement (non-deterministic, hard to test; may assist fingering later).
- **Impact:** New research spike (bean). Adds optional model downloads: transcription (~a few MB) and stem separation (~80 MB, heavy: needs WebGPU on web, better on native). Transcription quality limits results for dense mixes; piano-only recordings work best. Revisit if on-device inference is too slow on web.

### D12. Skill backbone with profile variants

- **Status:** accepted 2026-10-16
- **Decided by:** Yuri Olive
- **Context:** Kids and adults need different pacing and tone, and learners stay motivated by music they like (e.g. classical vs pop). The reference app solves this with many forked course variants (10 of 48 courses are Kids versions; Piano Basics 1 has 8 variants), which multiplies authoring work.
- **Decision:** Each module has a fixed skill backbone (ordered nodes, pass rules). Content varies along three axes: audience (`kids`, `teen_adult`), taste (`classical`, `folk_world`, `jazz_blues`, `hymns_spirituals`, `originals_pop`) and locale. Nodes declare defaults plus per-axis overrides and 2–4 song slots; the user's profile resolves them. Progress is keyed by backbone node.
- **Why:** One pedagogy, many flavours; adding a taste means filling song slots, not forking courses; switching profile keeps progress.
- **Alternatives:** Fork whole courses per audience (reference app's way: authoring and QA cost grows per variant); single course for everyone (weaker motivation, poor fit for kids).
- **Impact:** Content format gains `audience` overrides and `songs` slots per node (content-format spec update when accepted); onboarding asks age band and styles; each node needs PD songs per taste, which grows the song-curation work (bean piano-ts7r).

## Proposed

### D13. One polished arena-style theme, main menu with nav bar, and two-level course trail

- **Status:** proposed
- **Context:** Menus used stock Material widgets. The user wants them to look like a polished modern game (Fortnite-level finish), with one theme rather than kid/adult skins, a main menu with a navigation bar (courses are not the only mode: a practice mode is coming), and a course map that groups modules → submodules → tasks with an outer and an inner trail. The reference app's structure is section → course → journey nodes (named, several levels each) → stages.
- **Decision:** One theme drawn in code (`app/lib/ui/game/`): night-violet arena backdrop, chamfered cards/buttons, heavy uppercase type, yellow CTAs, cyan accents, gold stars, crisp motion. Main menu with top bar and bottom nav (Learn, Practice, Profile). Learn shows a continue card, section headers, an outer trail of module cards (courses) that expand into an inner trail of submodules (journey nodes), and a task sheet (levels). `courses.json` gains `sections` and `status: "planned"` modules. See [visual-style.md](specs/visual-style.md). Display font Audiowide (SIL OFL 1.1, bundled with its license). Menu sounds are synthesised at runtime (Web Audio on web, silent elsewhere for now), mutable in Profile. Original style only: no third-party assets, logos or characters.
- **Why:** Matches the reference hierarchy without inventing new content levels; one theme is cheaper to polish than two; the nav bar leaves room for practice and profile; code-drawn art is license-clean and light.
- **Alternatives:** Two skins (kids/adults; rejected by the user: harder to polish both); single flat list of nodes (no grouping, doesn't scale to many modules); named sub-groups inside journeys (not in the reference; star gates/bosses already split journeys); raster/AI art (license and provenance checks, weight); Material defaults (not game-like).
- **Impact:** Menus and overlays use the kit; HomePage becomes a tabbed shell. Content format and linter accept `sections` and planned courses. Adds one 70 KB font file. Practice screen keeps its own palette for now.

### D14. Backing band parts (`DRUMS`, `BASS`) in song files

- **Status:** proposed
- **Context:** Play-along feels thin with only piano accompaniment; the reference app plays a band under the learner. We need drums and bass without video, licensed audio stems or large sample packs.
- **Decision:** Song bars may hold optional `DRUMS` and `BASS` parts in the existing note notation, played by the app and never graded (like `ACC`). `DRUMS` pitches are General MIDI percussion numbers limited to kick 36, snare 38, closed hi-hat 42, open hi-hat 46, crash 49. Core tags every timed note with its `Part`; the bridge exposes it as `NoteView.part_name`. On web, drums are synthesized (noise + oscillators) and bass is a filtered sawtooth/sine voice; no new sample files.
- **Why:** One notation and one lint for all parts; GM numbers keep parts portable to MIDI export and a future native synth; synthesis adds zero download size and no licensing questions.
- **Alternatives:** Pre-rendered backing audio per song (big files, tempo changes need time-stretching, drifts from the audio clock); drum sample kit (download size, sourcing CC0 samples); free-form drum token syntax (`k s h`) (second parser, no MIDI mapping).
- **Addendum (proposed):** a fourth part, `PAD` (synthesized strings: detuned saws, slow envelope), and one gain bus per part with a default mix and `setPartLevel()`. Same rules: app-played, never graded. Also `CHOIR`: wordless "ooh" voices by formant synthesis (no recorded vocals, so no licensing or size cost).
- **Impact:** `content-format.md` backing-parts section; schema allows `ACC`/`DRUMS`/`BASS`; `PianoSynth` gains `drum()` and `bass()` (silent stub off web until the native audio engine). Synth drums sound basic; revisit with sampled kits if users find them weak. Our own drum/bass parts added to Ode to Joy and Hot Cross Buns.
