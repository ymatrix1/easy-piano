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
| OQ10 | Licence of the melody-model weights, given CC-BY-SA training data (Mutopia) and CC-BY dataset terms (PDMX)? | Unsettled whether weights are an "adaptation" of training data. Options: CC-BY-SA-4.0 weights (safe if they are), CC0/MIT (if not), or drop CC-BY-SA sources. Decide before shipping weights; provenance record lists every source either way |
