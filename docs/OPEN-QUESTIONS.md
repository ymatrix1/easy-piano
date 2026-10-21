# Open questions

| # | Question | Notes |
|---|---|---|
| OQ1 | Final project name? | Working name Easy Piano (repo). Candidates: Fermata (wait-mode pun), Tasto, Klavia. Check GitHub/stores/trademark collisions |
| OQ2 | Code license: MPL-2.0, GPL-3.0 or Apache-2.0? | GPL blocks closed forks but complicates App Store; MPL is a middle ground |
| OQ3 | Piano samples: which open soundfont, and size budget for bundle vs download? | Salamander Grand (CC-BY) is ~300 MB raw; need a compressed 10–20 MB cut |
| OQ4 | Hand model in scenes: 2D vector hands drawn in code, or Rive asset? | 2D code-driven is data-aware; Rive looks better. Spike in Phase 2 |
| OQ5 | Sync: none, self-hostable server, or file export/import? | D8 says local-first |
| OQ6 | Voice-over in scenes: none, TTS at build time, or recorded? | TTS keeps localization cheap |
| OQ7 | Does Flutter Web + flutter_rust_bridge wasm meet the latency budget? | Phase 0 spike answers |
| OQ9 | How do we detect a learner's current level (placement) and choose their start node? | Until answered every course and node stays open; star gates score progress but never lock. Draft: [specs/placement.md](specs/placement.md). Bean piano-vg8h |
| OQ8 | How far do we mirror Simply Piano's course list vs design our own order? | Proposal in [curriculum](specs/curriculum.md) |
| OQ10 | Licence and shippability of the melody-model weights: CC-BY-SA training data (Mutopia), CC-BY dataset terms (PDMX), untested NMD transcriptions (D18), and **copyrighted melodies in flagged PDMX tunes (D21)**? | Open: whether weights are an "adaptation" of training data, and whether memorised copyrighted melodies make the weights or outputs infringing. Options: CC-BY-SA-4.0 weights; CC0/MIT; retrain without flagged or CC-BY-SA sources before shipping. Provenance per tune allows any of these. Proposal: D24 (CC-BY-SA-4.0, full disclosure, release asset). Decide before shipping weights |
| OQ11 | Accept mic timing logic in Dart instead of Rust `core` (rule 7)? | [D27](DECISIONS.md): onset/chord detection, calibration median and the MIDI/mic echo window run in Dart on web (AudioWorklet → Dart, no per-chunk FFI). Grading stays in `core`. Options: accept for web, or port `NoteDetector` to `core` with the native audio thread. D27 stays proposed until answered |
