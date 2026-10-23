---
# piano-74mn
title: Improve module card color variety and green tone legibility
status: completed
type: task
priority: normal
created_at: 2026-10-23T13:29:01Z
updated_at: 2026-10-23T13:59:43Z
---

Context
Module cards in LearnTab cycle through only 3 colors (blue, purple, green), repeating constantly down the course list. In addition, GameTone.green is overly bright/neon, making white title and subtitle text on green cards difficult to read.
Blocked by: none

Higher Goal
Keep course navigation visually diverse, vibrant, and comfortably legible across all modules.

Acceptance Criteria
- [x] Darken/enrich GameTone.green gradient so white text and module metadata have clear, readable contrast
- [x] Expand module card tone sequence in LearnTab with additional tones (e.g., teal/cyan, gold/amber, coral/red, violet, azure) for visual variety
- [x] All Flutter analyze and test checks pass

Out of Scope
- Redesigning the entire LearnTab layout or card geometry

Summary of Changes
- Enriched GameTone.green gradient in pp/lib/ui/game/game_theme.dart (top #22A055, bottom #0D5E30, label Colors.white) to guarantee high-contrast readability for white titles and kicker text.
- Added GameTone.cyan and GameTone.orange tones to the game theme.
- Expanded LearnTab._tones sequence to 6 distinct tones: [blue, purple, orange, green, cyan, red], removing the 3-color monotony across course modules.
- Updated docs/specs/visual-style.md to reflect the expanded GameTone set and module card cycle.
