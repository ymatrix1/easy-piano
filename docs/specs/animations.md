# Animation scenes (video replacement)

Status: draft. See [D4](../DECISIONS.md). No video files in the app.

## Scene model

A scene is a JSON timeline rendered by the app's own painters.

```json
{
  "id": "pb1.finger-numbers",
  "duration_beats": 32, "bpm": 60,
  "layers": ["keyboard", "hands", "staff", "caption"],
  "tracks": [
    {"at": 0,  "caption": "str:pb1.finger.intro"},
    {"at": 4,  "hand": "R", "pose": "rest", "on": "C4"},
    {"at": 6,  "hand": "R", "finger": 1, "press": "C4", "label": "1"},
    {"at": 8,  "hand": "R", "finger": 2, "press": "D4", "label": "2"},
    {"at": 16, "staff": "treble", "notes": "C4:1/4 D4:1/4 E4:1/4 F4:1/4 G4:1"},
    {"at": 24, "prompt": "your_turn"}
  ]
}
```

Primitives: camera (zoom keyboard range), key highlight, hand pose / finger press, staff notes with playhead, arrows, captions (`str:` keys → localized), synth audio of pressed notes, optional Rive mascot.

Properties: localizable, tempo-scalable, mirror (left-handed), interruptible ("try it now" turns into `wait` stage).

## Pipeline from reference video

Reference videos stay local ([content rule](../../.agents/rules/content-and-licensing.md)). For each:

1. `agy -p "<prompt>" --add-dir <video dir> --output-format json` (Google Antigravity CLI, multimodal) produces a **scene brief**: teaching goal, beats, what is shown on keyboard/hands, captions paraphrased in our words, duration.
2. Brief saved to `docs/research/scene-briefs/<id>.md` (our words, no transcript copy).
3. Author writes original scene JSON from brief; lint; preview.

Prompt template lives in `.agents/skills/video-to-scene/SKILL.md`.

## Acceptance

- [ ] Scene player renders keyboard, hands, staff, captions
- [ ] 10 Piano Basics 1 scenes authored
- [ ] Scene file ≤ 10 KB each
