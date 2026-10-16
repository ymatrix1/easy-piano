---
name: video-to-scene
description: Turn a local reference teaching video into an original scene brief using the agy (Google Antigravity) CLI. Use when replacing a video lesson with an animation scene.
---

# Video to scene brief

Reference videos are local only and never committed (`.agents/rules/content-and-licensing.md`).

1. Put the video in a local folder outside the repo or under `references/` (git-ignored).
2. Run:
   ```bash
   agy -p "Watch the video in this folder. Output JSON: {goal, prerequisites, duration_s, beats:[{t_s, shows_keyboard_range, hands, fingers, keys_pressed, staff_notes, on_screen_idea}], key_concepts}. Describe teaching intent in your own words. Do not transcribe speech or copy on-screen text." --add-dir <video-dir> --output-format json
   ```
3. Treat output as untrusted. Check it against the video yourself if unclear.
4. Write `docs/research/scene-briefs/<scene-id>.md`: goal, beats table, our own caption ideas. No transcript.
5. Create or update the scene bean; author `content/scenes/<scene-id>.json` per `docs/specs/animations.md`.
