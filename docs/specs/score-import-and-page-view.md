# Score Import & Static Multi-System Page View Specification

## Overview
This specification details the architecture, design, and user experience for:
1. **Multi-Format Score Importer**: Ingesting external music formats (**MusicXML**, **ABC notation**, **LilyPond**, and **MIDI**) into Easy Piano's unified internal `Song` model.
2. **Static Multi-System Page View**: Displaying whole compositions broken across multi-system vertical pages with justified measure spacing for score study and sheet music printing, modeled after MuseScore's `pagelayout.cpp` and `scorepageviewlayout.cpp`.
3. **UX & Entry Points**: Discoverable UI elements in the app (Practice Tab card, TopBar action, Drag-and-Drop) enabling seamless imports and mode switching between interactive play-along and static score study.

---

## 1. Reference Architecture & Benchmark Analysis

### 1.1 `sightread.dev` Benchmark Analysis
- **Parser Pipeline**:
  - `parse-xml.ts`: Parses uncompressed and compressed (`.mxl` zip) MusicXML. Extracts part lists, attributes (`divisions`, `key`, `time`, `staves`, `clef`), measures, notes (pitch, duration, ties, rests), and voice tracks.
  - `parse-midi.ts`: Parses standard MIDI files (Type 0 and 1) via `@tonejs/midi`, quantizing ticks to musical subdivisions and assigning channels/tracks to left/right hands based on pitch split or track metadata.
  - Serialization: Standardizes input into an internal `SongData` representation: `{ id, title, composer, timeSignature, tempo, measures, notes }`.
- **UI & UX Flow**:
  - Central "Select Song" page with search bar, folder management, and upload button.
  - Song preview modal showing metadata, preview playback, and direct launch into visualizer.
  - Drag-and-drop support anywhere on the browser window for immediate playback.

### 1.2 MuseScore Studio (`references/MuseScore/src/engraving/rendering/score/`)
- **`pagelayout.cpp`**:
  - Calculates page dimensions, page margins, and printable area ($W_{\text{printable}} = W_{\text{page}} - \text{margin}_{\text{left}} - \text{margin}_{\text{right}}$).
  - Distributes measures into horizontal systems based on measure minimum stretch widths, avoiding overcrowded or sparse lines.
  - Calculates vertical page distribution and inter-system spacing (grand staff brace, system distance).
- **`scorepageviewlayout.cpp`**:
  - Coordinates multi-page coordinate grids (single page, continuous vertical scroll, or side-by-side spread).
  - Handles system justification: measures within each system stretch proportionally ($w_i' = w_i \times \frac{W_{\text{system}}}{\sum w_i}$) so the right barline aligns perfectly with the right page margin.

### 1.3 Simply Piano Decompile Analysis (`references/app-ss`)
- In Simply Piano, sheet music is primarily tied to interactive scrolling tracks.
- When opening song details or previews, clean metadata cards summarize tempo, difficulty, hand position, and key signature before loading interactive practice stages.
- External import is not supported in Simply Piano, giving Easy Piano a significant unique advantage in open learning.

---

## 2. Technical Design & Core Models

### 2.1 Multi-Format Import Architecture (`piano-gy3o`)
The parser layer lives primarily in Rust `core` (with Dart FFI bindings) to guarantee blazing fast parsing across Web (Wasm), Desktop, and Mobile:

```
[ External File ] (.xml, .mxl, .mid, .midi, .abc, .ly)
       │
       ▼
┌──────────────────────────────────────────────┐
│            Score Import Engine               │
│                                              │
│  ┌──────────────┐      ┌──────────────────┐  │
│  │ MusicXML     │      │ MIDI             │  │
│  │ (xml / mxl)  │      │ (mid / midi)     │  │
│  └──────┬───────┘      └────────┬─────────┘  │
│         │                       │            │
│  ┌──────┴───────┐      ┌────────┴─────────┐  │
│  │ ABC Notation │      │ LilyPond Subset  │  │
│  │ (.abc)       │      │ (.ly)            │  │
│  └──────┬───────┘      └────────┬─────────┘  │
│         └───────────┬───────────┘            │
│                     ▼                        │
│          Unified `Song` AST                  │
│       (Metadata, Tracks, Measures)           │
└─────────────────────┬────────────────────────┘
                      │
                      ▼
   [ Easy Piano Content Repo / Custom DB ]
```

#### Format Handling:
1. **MusicXML (`.xml`, `.musicxml`, `.mxl`)**:
   - Parses `<score-partwise>`, `<measure>`, `<attributes>` (clef, key, time), `<note>` (pitch, step, octave, duration, rest, tie, voice, staff).
   - Decompresses zip container for `.mxl` files.
2. **Standard MIDI (`.mid`, `.midi`)**:
   - Parses note_on/note_off ticks, tempo change events, and time signature meta-events.
   - Intelligent two-hand split:
     - If 2+ tracks exist: Track 1 $\to$ Right hand (Treble), Track 2 $\to$ Left hand (Bass).
     - If single track: split around middle C (MIDI pitch 60) with voice smoothing.
3. **ABC Notation (`.abc`)**:
   - Parses tune headers (`X:`, `T:`, `M:`, `L:`, `Q:`, `K:`, `V:`) and body tokens (pitches, note lengths, bar lines, chords, tuplets).
4. **LilyPond (`.ly`)**:
   - Subset parser for standard piano staves (`\score { \new PianoStaff << \new Staff ... \new Staff ... >> }`).

---

### 2.2 Static Multi-System Score Page View (`piano-ev1n`)
Unlike `PracticeStage` (which scrolls horizontally in real-time tied to audio beats), the **Static Score View** displays complete pages for visual study, rehearsal, and printing.

#### Algorithmic Components (`app/lib/ui/staff/score_page_layout.dart`):
1. **Measure Minimum Width Estimation**:
   - Each measure requires minimum width $W_{\min} = W_{\text{clef/key/meter}} + \sum W_{\text{note}} + W_{\text{padding}}$.
2. **System Line Breaking**:
   - Greedy line breaker or Knuth-Plass style penalty-minimizing break:
     Fits measures $[m_a \dots m_b]$ onto line $k$ such that $\sum_{i=a}^b W_{\min}(i) \le W_{\text{page\_content}}$.
3. **Horizontal System Justification**:
   - Distributes remaining whitespace $\Delta W = W_{\text{page\_content}} - \sum_{i=a}^b W_{\min}(i)$ proportionally among measures:
     $$W_{\text{justified}}(i) = W_{\min}(i) + \Delta W \cdot \frac{W_{\min}(i)}{\sum W_{\min}}$$
4. **Vertical Page Flow & Pagination**:
   - Computes systems per page based on grand staff height, system gap, and vertical margins.
   - Generates pages $1, 2, \dots, N$ in a vertical scroll or paginated carousel with page numbers and headers.

---

## 3. UI/UX Specifications & User Journey (`piano-uy13`)

### 3.1 Primary Entry Points

#### 1. Practice Tab Card ("Song Library & Custom Scores")
- Located in `PracticeTab` (`app/lib/home/other_tabs.dart`):
  - Card Title: **Song Library**
  - Subtitle: *Browse songs or import MusicXML, MIDI, ABC & LilyPond*
  - Tone: Red / Violet gradient.
  - Clicking opens the `SongLibraryPage`.

#### 2. TopBar Quick Action (Desktop & Web)
- On the global header or navigation bar:
  - An **Import** icon button (`Icons.file_upload_outlined` / `Icons.library_add_rounded`).
  - Clicking immediately prompts the native file picker or shows the import dialog.

#### 3. Drag-and-Drop Drop Target
- The app window accepts dragged files (`.xml`, `.mxl`, `.mid`, `.abc`, `.ly`).
- On drag hover: An animated glassmorphic overlay appears: *"Drop score file to import"*.
- On drop: Automatically parses, adds to library, and displays the song preview modal.

### 3.2 View Mode Switching (In-Song Navigation)
When a song/level is opened, the user can toggle between:
- **Practice Mode (Scroll)**: Real-time interactive canvas, pitch detection/MIDI input, moving playhead.
- **Study / Sheet Mode (Pages)**: Multi-system static pages, zoom in/out, page flipper, export PDF / print.

```
┌──────────────────────────────────────────────────────────┐
│  [< Back]  Fur Elise - L. v. Beethoven      [Study | Play]│
├──────────────────────────────────────────────────────────┤
│                                                          │
│  [Page 1 / 3]                                  [Zoom +/-]│
│  ┌────────────────────────────────────────────────────┐  │
│  │ 𝄞 𝄢 ──|────|────|────|────|───                     │  │
│  │                                                    │  │
│  │ 𝄞 𝄢 ──|────|────|────|────|───                     │  │
│  │                                                    │  │
│  │ 𝄞 𝄢 ──|────|────|────|────|───                     │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  [ Print / PDF ]                      [ Start Interactive ]│
└──────────────────────────────────────────────────────────┘
```

---

## 4. Work Breakdown & Phasing

| Phase / PR | Bean ID | Scope & Deliverables | Verification / Evidence |
|---|---|---|---|
| **PR 1: Docs & Spec** | *Current* | Architecture spec, MuseScore & sightread analysis, bean plan. | Docs committed, reviewed. |
| **PR 2: Page Layout** | `piano-ev1n` | `score_page_layout.dart`, Knuth-Plass measure breaks, system justification, static page view UI. | `app/test/ui/staff/score_page_layout_test.dart` passes. |
| **PR 3: Core Importer** | `piano-gy3o` | Parsers for MusicXML, MIDI, ABC, LilyPond into AST in `core` + FFI. **Status:** parsers, AST, FFI `import_score` and conversion to the content `Song` done (`core/src/score_import/`, `piano-t6rt`). | `cargo test --manifest-path core/Cargo.toml` (score_import tests). |
| **PR 4: Import UI & Library**| `piano-uy13` | Custom scores library, file drop target, PracticeTab card, TopBar action. | `flutter test` widget tests for library and drop target. |

---

## 5. Status, Limitations and Open Items

### 5.1 Status
- **Done (`piano-gy3o`, PR 3 parsers):** `core/src/score_import/` reads MusicXML (`.xml`, `.musicxml`, `.mxl`), MIDI (`.mid`, `.midi`), ABC (`.abc`) and a LilyPond subset (`.ly`) into a format-independent `ImportedScore` (notes in quarter-note beats with hand, measures with time and key, tempo, title, composer). MusicXML also retains note articulations (staccato, accent, tenuto, fermata) and expression spans/marks (slurs, dynamics, hairpins, damper pedal). Other parsers currently return no expression marks. Entry point: `score_import::import(file_name, bytes)`.
- **Not done:**
  - Import UI, library, drop target: `piano-uy13`.
  - Done in `piano-t6rt`: FFI `import_score` and conversion to the content `Song` (section 5.5).
  - Region filter for `restricted_in` songs: `piano-7os5`.
- **Test evidence:** unit tests with inline fixtures, and real files checked against independent oracles (core/tests/score_import_real.rs, see 5.3).

### 5.2 Known limitations
Each limitation is a deliberate scope cut, not a bug, unless marked "bug candidate".

**MusicXML**
- Only `score-partwise`. `score-timewise` returns an error. Decided (piano-tgsm): stays rejected. MuseScore, Finale, Sibelius and OpenScore export partwise; timewise support is a new bean if a real source needs it.
- Grace notes are skipped: they take no time and their pitches are not imported. Decided (piano-tgsm), same in all formats: ABC `{...}`, LilyPond `\grace`, `\acciaccatura`, `\appoggiatura` and the grace part of `\afterGrace`. Playing ornaments is out of scope.
- Ties are merged only within the same hand and pitch, and only when the end of the first note meets the start of the next.
- Hands come from the staff and clef of each note. Piano parts: when a part has two or more staves, only those parts are read (a sung line or another instrument is left out). Without any such part, every part is read. Two piano parts (four staves) are both read, with hands by staff, so a duet is not split by player.
- Measures come from the first part that is read. Later parts use the same bar grid.
- Pickup bars (anacrusis) use the actual length of the bar. Their `number` attribute is kept as written.
- Clef and key changes mid-piece are read per measure. `ImportedScore.right_clef` and `left_clef` only record the clef at the start.
- Measure length (fixed in piano-tgsm): a regular bar lasts its time signature even when every voice ends early, so later bars keep their place. A bar longer than its time signature uses its longest voice. An implicit pickup (`implicit="yes"`) has the length of its notes.

**MIDI**
- SMPTE time division is rejected.
- Hands: with two or more note tracks, track 1 is the right hand, track 2 the left, and further tracks follow their average pitch. With a single note track, each note is split at middle C. This is a heuristic. It does not read the source's own staff information.
- Channel 10 (drums) is ignored.
- Time and key signatures are read from every track. Changes that fall inside a bar are kept on their tick, but measure boundaries are computed from the time signature in force at each bar start.
- No lyrics, controllers, pedal or program changes are kept.

**ABC**
- Only the first tune in a file is read. A blank line ends the tune.
- Meter changes in the body (`M:` lines and `[M:...]`) are read (piano-tgsm). A change starts a new bar length at the furthest voice position. `L`, `Q` and `K` written inside the body are ignored; key changes are not read.
- `Z` (multi-bar rest) is approximated as bars of the header meter.
- Voices (`V:`) are read with `clef=bass` (left hand) or default (right hand). Other clefs are treated as the right hand.
- Chord symbols, decorations, lyrics (`w:`) and grace notes `{...}` are skipped.
- Accidentals reset at every bar line, as in ABC. Ties `-` join notes of the same pitch.

**LilyPond (subset)**
- Supported: `\header` (title, composer), `\score`, `\new Staff`, `\context Staff = ...`, `\new PianoStaff`, `<< >>`, `\\` voices, `\relative`, `\transpose from to` (interval only), music variables (`right = { ... }` used as `\right`), `\clef`, `\key`, `\time`, `\tempo`, `\repeat unfold`, `\times`, chords, ties `~`, rests `r` `R`, spacers `s`, cautionary accidentals `!` and `?` (no change of pitch).
- Ignored: `\alternative` (its branches are skipped), `\repeat volta` (played once), `\new Lyrics` and `\new ChordNames` (with their content), scheme words starting with `#`.
- Fixed (piano-tgsm): `\markup`, `\lyricmode`, `\lyrics`, `\addlyrics`, `\chordmode`, `\figuremode`, `\layout`, `\midi`, `\paper`, `\with` and grace blocks are skipped with their arguments, so words such as `a` in a markup are not notes. `\override`, `\revert` and `\set` drop their property path and `=`; the value is a scheme word or a string.
- Pitch names are English (`c d e f g a b`, with `is` and `es` suffixes). Dutch `h` and non-standard names are rejected.
- `\key` applies to plain note names, as in LilyPond. `\relative` uses the nearest pitch within a fourth.

**All formats**
- Measure grid is computed from the time signature in force. Mid-piece meter changes are read in all formats: MIDI from meta events, LilyPond from `\time`, ABC from `M:` and `[M:...]` (piano-tgsm). Key changes are read in MIDI and LilyPond, not in ABC.
- Fingering, lyrics, and dynamic velocity values are not imported. ABC decorations and LilyPond articulation syntax are not imported. MusicXML expression positions are taken from the measure cursor; `<offset>` is not applied. Tie spans are merged into note durations; slurs remain separate expression spans.

### 5.3 Open items
- **Real-file validation (`piano-niz2`):** done for three files: Mutopia LilyPond (checked against its own MIDI export), OpenScore MuseScore 4.5.2 `.mxl` (piano part counted with an independent script), and a CC0 sequencer MIDI (checked with `mido`). Fixes from this check: piano part selection in MusicXML, `\transpose`, music variables and `\context` in LilyPond, cautionary accidentals. Not checked yet: PDMX, and a MIDI whose DAW origin is confirmed (the CC0 file has sequencer metadata but its origin is not documented). Sources and oracles: `core/tests/fixtures/score_import/SOURCES.md`.
- **Dependencies:** `quick-xml` 0.37 and `zip` 2 (deflate only) were added to `core`. See [D38](../DECISIONS.md) (proposed). The MIDI reader is in-house, [D39](../DECISIONS.md) (proposed).
- **Placement:** parsers live in `core` (app side), not only in `tools/content-cli`. [D37](../DECISIONS.md) (proposed) puts them there. It conflicts with the accepted [D3](../DECISIONS.md) line "MusicXML and MIDI supported only as import sources via CLI", which needs an explicit decision by the user.

### 5.4 Follow-up beans
- `piano-t6rt`: FFI and conversion to the content `Song` format. Done, see 5.5.
- `piano-uy13`: import UI, library and drop target.
- `piano-niz2`: validate parsers on real exported files (fixtures, expected notes, measures and hands).
- `piano-tgsm`: close parser gaps. Done: measure length, LilyPond text and settings as music, ABC mid-piece meter. Recorded as out of scope in 5.2: grace notes (time and pitch), timewise MusicXML.

### 5.5 Conversion to a content song (`piano-t6rt`)
`score_import::song::import_song_json(file_name, bytes)` parses a file and returns content song JSON; the FFI `import_score` (`app/rust/src/api/score_import.rs`) calls it. Decision: [D40](../DECISIONS.md) (proposed).

- Metadata: `title` and `composer` from the parser (fallbacks: file stem, `Unknown`); `arranger` `Imported`; `source` `custom`; `source_url` null; `license` and `composition_license` `user-provided`. The content lint rejects these values on purpose (shipped content only).
- Id: `custom-` plus the file stem as a lowercase slug (`Für Elise.mid` gives `custom-f-r-elise`).
- Tempo: `tempo_bpm` (quarter notes) times the beat unit over 4, clamped to 20-300; 120 when the file has no tempo.
- Layout: notes of one hand that start and end together form one chord token. A hand has at most two voices: the first in `RH`/`LH`, the second in `RH2`/`LH2`, which is added only in bars where it sounds. Voices are filled with rests. A note that crosses a bar line is split with `{tie}`. Durations are exact fractions of a whole note (triplets become `1/12` etc.); time is kept to 1/120 of a quarter.
- Key: the first measure's key signature (`Song.key`, a major tonic name).
- Limits (errors or ignored, to be fixed in a later bean if needed):
  - More than two voices in one hand at one moment: error `more than two voices in one hand at beat N`. Common in piano music with a held chord under moving notes; the import fails.
  - Meter change in the piece: error. `Song.time` has one value.
  - Key change in the piece: ignored (the notes keep their absolute pitch; only the key signature drawn is wrong after the change).
  - Measure grid comes from the parser (`ImportedMeasure`); pickup bars are padded by the grid, not shown as shorter.
  - No fingering, dynamics or lyrics (not in `ImportedScore`).
- Tests: `core/src/score_import/song.rs` (layout, ties, voices, errors, key and tempo, id slug, ABC round trip) and `app/rust/src/api/score_import.rs`.
- Not verified: the Web (wasm) build of the bridge, and an import from a real file; both belong to `piano-niz2` and the Web check of `piano-t6rt`. The import UI (`piano-uy13`) is not built yet, so no screen shows an imported song.
