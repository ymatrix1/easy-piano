# Methods library

Status: specified, not implemented ([D35](../DECISIONS.md), proposed; bean piano-d72v). Content rules: [D33](../DECISIONS.md), [content-format](content-format.md).

Optional method books (Mikrokosmos, later Burgmüller, Czerny, Beyer) next to the main path. They never lock anything and are not steps of the course.

## Navigation

| Level | Screen | Content |
|---|---|---|
| 1 | Learn tab | Main path only (sections `basic`, `main`). After the last section, one **Methods** card: title, number of methods, overall stars. Tap opens the library. |
| 2 | Methods library | One card per method: composer, title, level range, number of books, progress (stars / max). Filter chips: level (beginner, early intermediate, intermediate) and focus skill. |
| 3 | Method page | Short description (our own wording), books as collapsible sections (first unfinished one open), **Continue** button on the next unplayed piece. Pieces show stars like journey nodes. |
| 4 | Piece | Existing task sheet and level stages, unchanged. |

Rules:

- Method courses get no module number and no star gates; every piece is open.
- A piece restricted in the learner's region (`restricted_in`) is shown locked with the reason ("protected in your country until 2036"), not hidden. Until region detection exists (bean piano-7os5) nothing is locked.
- Back from a piece returns to the method page; back from the method page returns to the library.

## Data

New `content/methods.json`:

```json
{
  "methods": [
    {
      "id": "mikrokosmos",
      "title": "str:method.mikrokosmos.title",
      "composer": "Béla Bartók",
      "description": "str:method.mikrokosmos.desc",
      "levels": ["beginner", "early-intermediate", "intermediate"],
      "skills": ["reading", "rhythm", "independence"],
      "books": ["mikrokosmos-1"]
    }
  ]
}
```

- Each book is a course in `courses.json` with `"method": "mikrokosmos"` and no `section`; the `methods` section goes away. Course order inside a method follows `books`.
- Lint: every `books` id is a course whose `method` names this method; every course with `method` is listed in exactly one method; `str:` keys exist; `levels` and `skills` come from fixed lists.
- Off-ramp rule (difficulty, skill specs, similarity calibration) keys on `method` instead of the `methods` section.
- Progress: unchanged, per level id; the library and method page sum stars over the method's courses.
