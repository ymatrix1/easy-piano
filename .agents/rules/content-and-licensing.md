# Content and licensing

The app is open source; its content must be clean. See [D6](../../docs/DECISIONS.md).

- **Never commit** files, melodies-as-arranged, text, images, audio or video from Simply Piano (APK, CDN, screenshots). `references/` is git-ignored and stays local.
- Reference material is for learning **structure, sequencing and mechanics** only. Numeric stats (counts, bpm ranges, note ranges) are fine; transcribed arrangements are not.
- "Publicly visible" is not "free to reuse". A score is usable only when **both** hold:
  1. The arrangement license is CC0, public domain, CC-BY or CC-BY-SA (or we wrote it).
  2. The underlying composition is public domain (composer died > 70 years ago, or traditional) or openly licensed.
- Every song file records `source`, `source_url`, `arranger`, `license` and `composition_license`. CI rejects songs without them.
- Sources in order of preference: our own arrangement of a PD tune; Mutopia (LilyPond, PD/CC); IMSLP (check per file); MuseScore scores whose license field passes rule above, downloaded through the site's own export.
- Don't bulk-scrape any site. Fetch individual scores that pass the rule, respect ToS and robots.
- Fixtures and examples use PD tunes (Ode to Joy, Twinkle Twinkle, Jingle Bells, Minuet in G).

## Note: melody-model training data ([D21](../../docs/DECISIONS.md))

- The practice-tune model may be **trained** on flagged material, including pop, film and game melodies and PDMX licence-conflict scores, with style tags. This is a training-data exception only.
- No copyrighted melody, audio or arrangement is ever committed or shipped as content. Raw corpora stay in git-ignored `data/`.
- Every generated tune passes the similarity filter (`content-cli similar`, PR #34) before it is used as content.
