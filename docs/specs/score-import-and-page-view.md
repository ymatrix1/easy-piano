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
| **PR 3: Core Importer** | `piano-gy3o` | Parsers for MusicXML, MIDI, ABC, LilyPond into AST in `core` + FFI. **Status:** parsers and AST done (`core/src/score_import/`); FFI and conversion to the content `Song` pending in a follow-up bean. | `cargo test --manifest-path core/Cargo.toml` (score_import tests). |
| **PR 4: Import UI & Library**| `piano-uy13` | Custom scores library, file drop target, PracticeTab card, TopBar action. | `flutter test` widget tests for library and drop target. |

---

## 5. Status, Limitations and Open Items

### 5.1 Status
- **Done (`piano-gy3o`, PR 3 parsers):** `core/src/score_import/` reads MusicXML (`.xml`, `.musicxml`, `.mxl`), MIDI (`.mid`, `.midi`), ABC (`.abc`) and a LilyPond subset (`.ly`) into a format-independent `ImportedScore` (notes in quarter-note beats with hand, measures with time and key, tempo, title, composer). MusicXML also retains note articulations (staccato, accent, tenuto, fermata) and expression spans/marks (slurs, dynamics, hairpins, damper pedal). Other parsers currently return no expression marks. Entry point: `score_import::import(file_name, bytes)`.
- **Not done:**
  - FFI binding and conversion of `ImportedScore` into the content `Song` format: `piano-t6rt`.
  - Import UI, library, drop target: `piano-uy13`.
  - Region filter for `restricted_in` songs: `piano-7os5`.
- **Test evidence:** unit tests with inline fixtures only. No file produced by MuseScore, Mutopia, OpenScore or PDMX has been parsed yet (see 5.3).

### 5.2 Known limitations
Each limitation is a deliberate scope cut, not a bug, unless marked "bug candidate".

**MusicXML**
- Only `score-partwise`. `score-timewise` returns an error.
- Grace notes are skipped. Their time is not counted.
- Ties are merged only within the same hand and pitch, and only when the end of the first note meets the start of the next.
- Hands come from the staff and clef of each note. A part with more than two staves is mapped the same way, with no separate handling.
- Measures come from the first part. Later parts use the same bar grid.
- Pickup bars (anacrusis) use the actual length of the bar. Their `number` attribute is kept as written.
- Clef and key changes mid-piece are read per measure. `ImportedScore.right_clef` and `left_clef` only record the clef at the start.
- Bug candidate: measure duration uses the longest voice (`max_end`). A bar with an unfinished voice and a longer one gives the longest length, which may not match the printed bar.

**MIDI**
- SMPTE time division is rejected.
- Hands: with two or more note tracks, track 1 is the right hand, track 2 the left, and further tracks follow their average pitch. With a single note track, each note is split at middle C. This is a heuristic. It does not read the source's own staff information.
- Channel 10 (drums) is ignored.
- Time and key signatures are read from every track. Changes that fall inside a bar are kept on their tick, but measure boundaries are computed from the time signature in force at each bar start.
- No lyrics, controllers, pedal or program changes are kept.

**ABC**
- Only the first tune in a file is read. A blank line ends the tune.
- Header fields `M`, `L`, `Q`, `K` written inside the body are ignored. Only the header values apply.
- `Z` (multi-bar rest) is approximated as bars of the header meter.
- Voices (`V:`) are read with `clef=bass` (left hand) or default (right hand). Other clefs are treated as the right hand.
- Chord symbols, decorations, lyrics (`w:`) and grace notes `{...}` are skipped.
- Accidentals reset at every bar line, as in ABC. Ties `-` join notes of the same pitch.

**LilyPond (subset)**
- Supported: `\header` (title, composer), `\score`, `\new Staff`, `\new PianoStaff`, `<< >>`, `\\` voices, `\relative`, `\clef`, `\key`, `\time`, `\tempo`, `\repeat unfold`, `\times`, chords, ties `~`, rests `r` `R`, spacers `s`.
- Ignored: `\alternative` (its branches are skipped), `\repeat volta` (played once), `\new Lyrics` and `\new ChordNames` (with their content), scheme words starting with `#`.
- Not handled (bug candidate): the content of `\markup`, `\lyricmode` and `\override` blocks is read as music. Words that look like pitch names (for example `a`) can become notes. Fix in `piano-tgsm`.
- Pitch names are English (`c d e f g a b`, with `is` and `es` suffixes). Dutch `h` and non-standard names are rejected.
- `\key` applies to plain note names, as in LilyPond. `\relative` uses the nearest pitch within a fourth.

**All formats**
- Measure grid is computed from the time signature. Mid-piece meter changes inside the body of ABC and LilyPond are ignored; in MIDI they are read from meta events.
- Fingering, lyrics, and dynamic velocity values are not imported. ABC decorations and LilyPond articulation syntax are not imported. MusicXML expression positions are taken from the measure cursor; `<offset>` is not applied. Tie spans are merged into note durations; slurs remain separate expression spans.

### 5.3 Open items
- **Real-file validation (`piano-niz2`, see 5.4):** the parsers have not been run on files from MuseScore/OpenScore (`.mxl`), Mutopia (`.ly`), PDMX, or DAW MIDI exports. Results and any fixes go in that bean.
- **Dependencies:** `quick-xml` 0.37 and `zip` 2 (deflate only) were added to `core`. See [D38](../DECISIONS.md) (proposed). The MIDI reader is in-house, [D39](../DECISIONS.md) (proposed).
- **Placement:** parsers live in `core` (app side), not only in `tools/content-cli`. [D37](../DECISIONS.md) (proposed) puts them there. It conflicts with the accepted [D3](../DECISIONS.md) line "MusicXML and MIDI supported only as import sources via CLI", which needs an explicit decision by the user.

### 5.4 Follow-up beans
- `piano-t6rt`: FFI and conversion to the content `Song` format.
- `piano-uy13`: import UI, library and drop target.
- `piano-niz2`: validate parsers on real exported files (fixtures, expected notes, measures and hands).
- `piano-tgsm`: close parser gaps (the "bug candidate" in 5.2, grace notes, timewise MusicXML, mid-piece meter changes), or record them as out of scope.
