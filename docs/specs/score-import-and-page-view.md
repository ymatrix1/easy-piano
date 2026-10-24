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
| **PR 3: Core Importer** | `piano-gy3o` | Parsers for MusicXML, MIDI, ABC, LilyPond into AST in `core` + FFI. | `cargo test -p core` parses test files. |
| **PR 4: Import UI & Library**| `piano-uy13` | Custom scores library, file drop target, PracticeTab card, TopBar action. | `flutter test` widget tests for library and drop target. |
