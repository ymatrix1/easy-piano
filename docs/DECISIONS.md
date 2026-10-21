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
| [D14](#d14-backing-band-parts-drums-bass-in-song-files) | 2026-10-16 | Backing band parts in song files | proposed |
| [D15](#d15-web-hosting-on-cloudflare-pages) | 2026-10-16 | Web hosting on Cloudflare Pages | proposed |
| [D16](#d16-ui-strings-in-gen-l10n-arb-files-content-strings-in-contentstrings-five-launch-languages) | 2026-10-19 | UI strings in ARB, content strings in content/strings, five languages | proposed |
| [D17](#d17-generated-practice-songs-cc0-provenance-rubric-human-review) | 2026-10-20 | Generated practice songs: CC0, provenance, rubric, human review | proposed |
| [D18](#d18-nottingham-music-database-minus-ashover-in-the-melody-model-training-set) | 2026-10-20 | NMD (minus Ashover) in melody-model training | accepted |
| [D19](#d19-approved-training-corpora-for-the-melody-model) | 2026-10-20 | Approved melody-model training corpora | accepted; superseded in part by D21 |
| [D20](#d20-melody-model-design-compound-tokens-form-plan-fim-constrained-search) | 2026-10-20 | Melody model design | proposed |
| [D21](#d21-train-the-melody-model-on-everything-we-can-flagged-and-style-tagged) | 2026-10-20 | Train on everything we can, flagged and style-tagged; supersedes part of D19 | accepted |
| [D24](#d24-melody-model-weights-licence-storage-and-training-data-disclosure) | 2026-10-21 | Melody-model weights: licence, storage, disclosure | proposed |
| [D25](#d25-melody-model-decoding-masks-cover-the-taught-set-the-rubric-covers-patterns-and-fingering) | 2026-10-21 | Melody-model decoding: masks vs rubric | proposed |
| [D26](#d26-explainable-song-difficulty-level-from-skill-scores-and-a-monotonic-ordinal-model) | 2026-10-21 | Explainable song difficulty level from skill scores and a monotonic ordinal model | proposed |

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
- **Superseded in part by:** [D22](#d22-sampled-instruments-for-piano-and-backing-band-proposed) (proposed) replaces the synthesized sounds; the notation and part rules stay.

### D15. Web hosting on Cloudflare Pages

- **Status:** proposed
- **Context:** The web build (D9) needs COOP/COEP headers so the Rust/wasm core (flutter_rust_bridge, SharedArrayBuffer) loads. We want free static hosting and a test link per pull request.
- **Decision:** Host on Cloudflare Pages. GitHub Actions builds (Flutter + nightly Rust/wasm, not available in the Pages build image) and uploads with `wrangler pages deploy`: production from `main`, a preview per PR, linked in a PR comment. Headers come from `app/web/_headers`.
- **Why:** Native custom headers; automatic preview URLs; global CDN; free tier fits.
- **Alternatives:** GitHub Pages (no custom headers; needs the coi-serviceworker hack with an extra reload on first visit); Netlify (similar, smaller free build quota); Vercel (similar; commercial-use limits on the free plan).
- **Impact:** Two repo secrets (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`); site at `easy-piano.pages.dev`; any new cross-origin asset must send CORP/CORS headers or COEP blocks it.

### D16. UI strings in gen-l10n ARB files, content strings in `content/strings`; five launch languages

- **Status:** proposed
- **Context:** UI text was hard-coded English in `app/lib`; content already used `str:` keys in `content/strings/<locale>.json` (en, pt-BR), with the locale fixed at startup. We want en, pt-BR, es, fr, de, a language picker and live switching.
- **Decision:** App UI text moves to Flutter `gen-l10n` ARB files (`app/lib/l10n/`, `flutter_localizations`, `intl`). Lesson content keeps `content/strings/<tag>.json` with fallback active tag → base language → English. Language defaults to the device locale, can be picked in Profile, and is stored per device with `shared_preferences`. Note naming is per locale: letters for en/de (de uses H), fixed-do solfège for pt-BR/es/fr. Spec: [i18n.md](specs/i18n.md).
- **Why:** ARB gives typed getters, ICU plurals/placeholders, compile-time key checks and Material widget translations for free. Content stays editable by non-developers in the content pipeline, linted by `content-cli`, and can ship English-first (missing keys warn, not fail).
- **Alternatives:** Everything in `content/strings` (no type safety, no plurals, Material widgets untranslated); everything in ARB (content authors would edit app code; lessons need an app rebuild per string); `easy_localization`/`slang` packages (extra dependency, no gain over the SDK tool).
- **Impact:** New deps `flutter_localizations`, `intl`, `shared_preferences`. New UI text must go in `app_en.arb` and all other ARBs (test enforces). Translations are machine-assisted; native review wanted. Content lint prints warnings for untranslated keys.

### D17. Generated practice songs: CC0, provenance, rubric, human review

- **Status:** proposed
- **Context:** Essentials I-III have 54 levels; the reference course size is about 50 / 41 / 55 levels. Hand-writing every practice tune does not scale, so we want generated tunes (rules, PD variations, LLM via an agent skill, Magenta.js). Generated material raises three questions: license, traceability, and whether it only uses what was taught.
- **Decision:** Generated songs use `source: "generated"`, `license: "CC0-1.0"` and a required `generator` object (`method`, `tool`, `model`, `seed`, `source_song`, `prompt_ref`). Each targets a journey node (`spec_node`) and must pass the rubric (`core/src/rubric.rs`) against that node's taught set and `content/skill-specs/<course>.json`. Every generated song is reviewed by a human in its PR (played or listened to). Generation happens only in the content pipeline (tools, agent skills); the app never generates songs at runtime. Generated songs never widen the taught set.
- **Why:** CC0 is the simplest license for machine-made material whose copyright status is unclear, and lets anyone reuse it. Provenance lets us rerun, audit or remove a batch by method or model. The rubric turns "only what was taught" into a check CI can run, and human review catches what the rubric cannot (musicality, accidental likeness to a known tune). Offline generation keeps the app deterministic, small and free of model dependencies.
- **Alternatives:** CC-BY-SA like hand arrangements (attribution for machine output is muddled); no provenance field (cannot audit a model or method later); rubric as a guideline only (drift from the curriculum); runtime generation in the app ("endless practice", but untestable content, model size, and no review).
- **Impact:** Song format gains optional `generator` and `spec_node` (schema, `content-format.md`); lint runs the rubric; new `content specs` command and `docs/specs/skill-specs.md`. Next: `compose-song` skill, method spike with blind listening test (epic piano-bovj).

### D18. Nottingham Music Database (minus Ashover) in the melody-model training set

- **Status:** accepted
- **Decided by:** user, 2026-10-20 (PR #37 review)
- **Context:** The practice-tune model (bean epic piano-bovj) needs simple folk melodies. The Nottingham Music Database (NMD, ~1,000 traditional tunes in ABC) is the closest match to beginner style, but the original files carry [no licence grant](https://abc.sourceforge.net/NMD/), the [jukedeck clean-up](https://github.com/jukedeck/nottingham-dataset) is GPLv3, and the NMD page states the Ashover collection's IPR "reside with Mick Peat".
- **Decision:** Train on the **original** NMD ABC files only, **excluding the Ashover collection** and tunes credited to a named composer (`S:` line starting, case-insensitive, with "by", "composed", "written", "words and music" or "music by"). Never use the jukedeck GPLv3 files. NMD stays a separate corpus in the dataset manifest (`corpus: "nottingham"`) so it can be dropped and the model retrained.
- **Why:** Musically the best fit; the tunes are traditional, and ABC transcriptions of traditional melodies are treated as uncopyrightable facts. **Risk accepted:** treating these transcriptions as uncopyrightable is an **untested position** (no court ruling we know of), and there is no explicit grant.
- **Alternatives:** Skip NMD (smaller, less beginner-like data); use jukedeck GPLv3 files (would raise the question whether weights inherit GPL); ask the maintainers for a licence (slow, may not answer).
- **Impact:** Provenance record lists NMD with this risk. If challenged, drop `corpus: "nottingham"` and retrain; generated tunes are checked for similarity to the training set either way.

### D19. Approved training corpora for the melody model

- **Status:** accepted; **superseded in part by [D21](#d21-train-the-melody-model-on-everything-we-can-flagged-and-style-tagged)** (the pop/film/game exclusion and the PDMX screen as hard rejects)
- **Decided by:** user, 2026-10-20 (PR #37)
- **Context:** Model weights ship in the open-source app, so training data must be clean. Licence review: [melody-corpora.md](research/melody-corpora.md).
- **Decision:** Train only on OpenScore Lieder (composer death-year checked), Mutopia (PD / CC-BY / CC-BY-SA pieces, attribution kept), our own songs, PDMX `no_license_conflict` after the pop screen and a 50-tune sample approved by the user, and NMD per D18. Excluded: Essen (CCARH licence), Meertens (NC), The Session (no-LLM clause), music21 sets of unverified origin, IMSLP, all pop/film/game material. PD rule: public domain in both the EU/UK/Brazil life+70 regime (composer died ≤ 1955) and the US (published before 1931), or traditional.
- **Why:** Only these sources allow training and shipping weights without non-commercial, research-only or no-AI terms.
- **Alternatives:** Larger mixed-licence corpora (Lakh, MuseScore at large): rejected, weights would not be clean.
- **Impact:** Raw data stays in git-ignored `data/`; manifests record URL, licence and hash per file. CC-BY/CC-BY-SA sources need credits in the app. Weights licence is open (OQ10).

### D20. Melody model design: compound tokens, form plan, FIM, constrained search

- **Status:** proposed (approved in planning and relayed to this session; awaiting the user's direct confirmation)
- **Context:** We need original practice tunes conditioned on a course node's spec, generated in the browser.
- **Decision:** Small decoder-only transformer (5–15M params) exported to ONNX int8 for onnxruntime-web. Compound tokens (one step = pitch, duration, finger, kind) with a spec prefix; two-level generation (bar-level form plan: section letter, cadence, contour; then notes); fill-in-the-middle training on the same decoder; constrained search at inference (masking, many samples, ranking by spec coverage, cadence, repetition, melody score, similarity < 0.6) with the rubric as a hard gate; later preference tuning (DPO) on blind listening ratings. Spec: `docs/specs/melody-model.md` (added by PR #41).
- **Why:** Short sequences and a small model keep browser inference fast; the plan gives tunes form; FIM allows bar-level edits; search plus rubric guarantees level fit.
- **Alternatives:** Magenta.js MusicVAE (pretrained on non-clean data); rules-only generator (dull); a large model behind a server (breaks local-first, D8).
- **Impact:** Steps: corpora, converters + tokenizer, dataset, training on the user's GPU, ONNX + browser demo, evaluation.

### D21. Train the melody model on everything we can, flagged and style-tagged

- **Status:** accepted
- **Decided by:** user, 2026-10-20: "please include pop, film and game music in training"; "no i want to use the flagged tunes"; "can we create the model with everything we can but with tags and groups, genres"; licence-conflict scores "Include, flagged"; Chinese music: earlier "i just dont want chinese music", then "Chinese music: do your recommendation" (include, tagged)
- **Context:** D19 excluded pop/film/game material. The user wants modern styles in the model and accepted the risk after being told the weights ship in the open-source app.
- **Decision:** Supersedes D19's exclusion of pop, film and game material. PDMX screen rules (licence conflict, genre, untagged, no composer, pop name/title, third-party arrangement) no longer drop tunes; each tune keeps `flags`, and **flagged tunes are used in training**. Every tune carries **style tokens** (classical, folk, religious, world, children, pop, rock, soundtrack, game, jazz, electronic, chinese) from corpus and metadata, so generation picks the style. **Chinese music is included, tagged `STYLE_chinese`**, and generation avoids it unless asked. Hard rejects stay only for duplicates and length; corpora whose own licence forbids this use (Essen, Meertens, The Session) stay out unless the user decides otherwise. This covers **training data only**: no copyrighted melody, audio or arrangement is ever committed or shipped as content, and every generated tune passes the similarity filter (`content-cli similar` < 0.6 against the training set and a local pop corpus, PR #34) before use.
- **Why:** Modern-sounding practice tunes; the user owns the legal call.
- **Alternatives:** Keep D19 (clean only; style tokens trained on clean data); pop only as a similarity negative set; train on flagged data but ship only weights trained without it.
- **Impact:** **Known risk:** the weights may memorise copyrighted melodies from flagged tunes (including licence-conflict scores, whose own files say copyrighted), so they may not be clean, and generated tunes may echo them. Mitigations: per-tune provenance and flags allow dropping any corpus or flag and retraining; the similarity filter on every generated tune; [OQ10](OPEN-QUESTIONS.md). The content rule (`.agents/rules/content-and-licensing.md`) is unchanged for shipped content. Counts: `python -m melody_model.build` writes `data/melody/dataset/stats.json`, summarised in `docs/research/melody-dataset.md` (PR #45).

### D22. Sampled instruments for piano and backing band (proposed)

- **Status:** proposed
- **Context:** Users say play-along sounds like a chiptune. D14 synthesizes `DRUMS`/`BASS`/`PAD`/`CHOIR` (saws, noise) and the FluidR3 piano notes are cut at 3.1 s; no reverb, no dynamics, every app-played note at one velocity on the exact grid. Research: [instrument-samples.md](research/instrument-samples.md).
- **Decision:** Piano uses Salamander Grand Piano V3 (CC-BY 3.0, 29 MP3s C1–C8, full decay). `BASS`, `PAD`, `CHOIR` use FluidR3_GM electric bass (finger), string ensemble 1 and voice oohs (MIT, looped for long notes). `DRUMS` use one-shots mixed from Virtuosity Drums (CC0). Total audio 2.87 MB, band instruments lazy-loaded per song. Mix: per-part buses (kept, `setPartLevel` now relative to the default mix), reverb send from a generated impulse response, gentle bus compressor and limiter; the learner's own keys bypass the dynamics (no added look-ahead latency). App-played parts get expression in Dart (`app/lib/audio/backing.dart`): metric and phrase velocity, deterministic humanized timing of at most 3–8 ms on companion parts only, legato bass, pedalled `ACC` chords. Grading and song time are untouched (rule 7).
- **Why:** Real recordings are the only way to stop sounding synthetic; these three sets are the best openly licensed ones we found, and fit 20% of the 15 MB budget. Humanize stays a few ms and seeded, so the band stays locked to the audio clock and plays the same every time.
- **Alternatives:** Better synthesis (still synthetic, much work); VSCO-2 CE strings (CC0, more work to loop, bigger); Salamander velocity layers (~8 MB more); pre-rendered backing audio per song (D14 reasons); humanize in Rust core (it is playback colour, not timing or grading logic, so it stays next to the synth).
- **Impact:** New assets `app/assets/piano/` (replaced) and `app/assets/band/` with licence files. CC-BY needs an in-app credit (bean). Native platforms stay silent until the native audio engine (bean). `content-format.md` mix table and `practice-screen.md` updated. Menu SFX and metronome click remain synthesized.

### D23. Native audio output via WASAPI exclusive (Windows), gated on web latency

- **Status:** proposed
- **Context:** Browser audio output on the test PC costs 40 ms `outputLatency` on top of a 10 ms buffer, and `latencyHint` tuning changes nothing. `cpal` shared mode is stuck at the 10 ms system period. WASAPI exclusive: 2 of 5 test devices streamed at 3.0 and 3.3 ms periods; the driver reported a 3 ms minimum period on all 5. See [native-audio-latency.md](research/native-audio-latency.md). D1 sets the gate at 30 ms p95 MIDI to frame.
- **Decision:** Do not start native audio until the web MIDI p95 is measured on a real keyboard. If web p95 ≤ 30 ms, native audio stays a later improvement. If it is over, add an `audio/` Rust crate that plays the piano through WASAPI exclusive (PCM16, 48 kHz) on Windows with a shared-mode fallback, and CoreAudio/Oboe via `cpal` elsewhere, chosen after per-platform measurement.
- **Why:** Shared-mode paths (browser, `cpal`) cannot go below 10 ms; exclusive can. The cost is a native sampler, a bridge call for note on/off and per-platform backends, so it should be justified by a measured miss.
- **Alternatives:** `miniaudio` (same exclusive backend, permissive licence, not yet measured); `flutter_soloud` (smallest change, not yet measured); stay web-only and advise wired or ASIO-class audio devices; Oboe or CoreAudio directly instead of `cpal`.
- **Impact:** New `audio/` crate and a `PianoSynth` native implementation. Samples decoded to PCM at load. Exclusive mode blocks other apps from the device while held. Needs a Windows loopback test, an Android device and an Apple device before backends are final.

### D24. Melody-model weights: licence, storage and training-data disclosure

- **Status:** proposed
- **Context:** Model `melody-model-v1` (PR #47, model card `docs/models/melody-v1.md`) was trained under D21: flagged PDMX tunes (pop, film, game, licence-conflict scores), NMD transcriptions (D18), CC-BY-SA Mutopia pieces and CC-BY dataset terms (PDMX). Whether weights are an adaptation of their training data is unsettled (OQ10).
- **Decision:** (1) Weights are not committed to git; they are published as a GitHub Release asset (`melody-model-v1`), with sha256 for every file committed in `tools/melody-model/releases/melody-model-v1.json`; code verifies the hash before use. (2) The release and the model card disclose every corpus, the flags, their counts and the known risk. (3) Weights are released under **CC-BY-SA-4.0** with attribution to the training sources (the most restrictive licence among the openly licensed sources), and **no claim** that they are free of third-party rights. (4) Generated tunes stay CC0-1.0 (D17) and ship only after the rubric, the similarity filter (`content similar` < 0.5 against the training set) and human review.
- **Why:** Keeps the repository small and history clean; checksums make the shipped model auditable; CC-BY-SA is the safe choice if weights are adaptations; full disclosure lets anyone judge the risk the user accepted in D21.
- **Alternatives:** CC0 or MIT weights (simplest, but wrong if weights are adaptations of CC-BY-SA data); Git LFS (quota, history weight); keep weights private and ship only generated tunes (no browser demo, no reuse); retrain without flagged or CC-BY-SA data before release.
- **Impact:** A release step (manual, user-confirmed) per model version; the app or demo fetches from the release URL or CI copies the files into the web build, verifying sha256. Known risk: possible memorised copyrighted melodies in the weights; the similarity filter covers generated output, not the weights themselves.

### D25. Melody-model decoding: masks cover the taught set, the rubric covers patterns and fingering

- **Status:** proposed
- **Context:** D20 says decoding is masked from the node spec. The generator (PR #47) masks the step grammar, taught pitches per hand, the taught maximum leap, taught durations that fit the bar, rest values and chord size. It does not generate fingering and does not force `required` patterns (e.g. "uses F#", "a dotted rhythm"); 30% of candidates miss one.
- **Decision:** Keep masks for what a single step can decide; leave `required` patterns and finger spans to the rubric gate, which drops failing candidates (both gates fail closed). Fingering is added later by the arranger, not by the model.
- **Why:** A per-step mask cannot know that a later bar will add a required note; forcing patterns early distorts melodies. Filtering costs only extra samples (16 candidates per node, 70% pass).
- **Alternatives:** Pattern-aware constrained decoding (force a required pitch or rhythm in the last bars when still missing); a learned fingering head.
- **Impact:** More samples per node; pass rate reported per run. Follow-up: steer decoding toward missing patterns near the end of a tune.

### D26. Explainable song difficulty level from skill scores and a monotonic ordinal model

- **Status:** proposed
- **Context:** Several features need to know how hard a song is: melody-model training labels (today a crude `level_of` heuristic on range, fastest note, black keys, hands, chords, density), checks on generated tunes, personal song import with simplification (D11) and placement (OQ9). The rubric (D17) answers "uses only what was taught", not "how hard". D18-D25 are on main, hence D26.
- **Decision:** A pure Rust module `core/src/difficulty.rs` computes features per hand and per bar, groups them into 8 skill scores in 0..1 (reading, hand position, intervals, rhythm, key, coordination, texture, speed) and maps them to a level 1-10 with a cumulative-logit ordinal model whose weights are non-negative. Weights live in `core/data/difficulty-weights.json`, fitted by `tools/difficulty/calibrate.py` from course order, node envelopes, simplified-vs-original pairs and (when present locally) PDMX `complexity` as weak labels. Output: level, `node_fit` (earliest journey node whose taught set the song fits, computed with the rubric's own taught-set check), skill scores, hardest bars, plain reasons, and what exceeds a given node. `content level` exposes it; lint warns when a course song's level is far from its node. Spec: [specs/difficulty.md](specs/difficulty.md).
- **Why:** Skill scores are explainable ("hard because of 16ths and hand shifts") and map to course concepts. Non-negative weights over features that only grow with difficulty make the level monotonic: more of any difficulty never lowers it, which a learner and an author can trust. An ordinal model fits 10 ordered levels with few parameters, so ~40 course songs can calibrate it. One Rust implementation serves the app, the CLI and Python (via the CLI), so labels, checks and the app never disagree.
- **Alternatives:** Keep `level_of` (unexplained, not tied to the course); hand-set thresholds per feature (no calibration, brittle); gradient-boosted or neural regressor on PDMX (opaque, not monotonic, PDMX labels are coarse 0-3 and uploader-set); level = node index from the rubric alone (only defined for songs inside the course's taught set, says nothing above Essentials III).
- **Impact:** New core module, weights JSON, `content level` command, lint warning, calibration script. Follow-ups: replace the melody model's `level_of` (bean piano-9aw0), use in import and placement. Weights must be refitted when course content changes a lot; lint's warning shows drift.

### D27. Web mic input: Dart onset + harmonic-salience detector, calibrated offset, app sound muted

- **Status:** proposed
- **Context:** Students without MIDI (acoustic or non-MIDI digital piano) can't play. Core already grades `Input::Mic` with its own window. The input spec planned Rust YIN/MPM in a native audio thread, which doesn't exist yet; web is the shipping platform and Piano Basics uses chords.
- **Decision:** On web, capture with `getUserMedia` (no echo cancellation/noise suppression/AGC) and an AudioWorklet; detect notes in pure Dart (`NoteDetector`: spectral-flux onsets, then greedy harmonic-salience picking on the energy that is new since the onset, up to 4 notes). Emit the MIDI path's `NoteEvent` with the onset time minus a calibrated offset stored per input device; the session runs with `Input::Mic`. MIDI keeps working alongside (a mic echo of a MIDI key within 350 ms is dropped). In mic mode the app's own piano, metronome and backing are silent after the count-in. Calibration uses a visual cue.
- **Why:** Handles beginner chords, which YIN/MPM can't; no model download or runtime; deterministic and unit-testable in Dart; works in the existing web build without new FFI. Muting is simpler and more reliable than echo cancellation, which distorts piano tones. Grading stays in Rust `core`; the detector only produces input events. **Deviation from rule 7 to accept or reject:** onset/chord detection, the calibration median and the echo window are timing-related logic in Dart, not `core` ([OQ11](OPEN-QUESTIONS.md)). This decision stays `proposed` until that is answered.
- **Alternatives:** Rust YIN/MPM in core via wasm (mono only; per-chunk FFI); Basic Pitch ONNX (Apache-2.0, chords, but ~20 MB runtime+model and ~0.5–1 s windows); browser echo cancellation instead of muting (smears notes, still leaks); audio click calibration (the mic hears the speaker click).
- **Impact:** New `app/lib/input/mic/`, `app/web/mic_worklet.js`, fixture generator `tools/mic_fixtures.py` (output git-ignored) and scorer `app/tool/mic_eval.dart`. Held-out fixture F1 0.829 on the Salamander piano (noisy 0.763); octave and fifth doublings report only one of the two notes (doubled-chord recall 0.53); bass below C3 weak; latency figures are computed from the algorithm, not measured on a device; real recordings, Safari/iOS and device latency are deferred (beans piano-czsj, piano-m4r9) ([research](research/mic-input.md)). Native platforms keep a stub until the native audio engine.
