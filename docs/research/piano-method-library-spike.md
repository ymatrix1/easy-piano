# Piano method library spike

- **Checked:** 2026-10-21
- **Sources:** [Brazilian Copyright Law 9.610/1998, art. 41](https://www.planalto.gov.br/ccivil_03/leis/l9610.htm); [University of Rochester score record for Burgmüller Op. 100](https://urresearch.rochester.edu/institutionalPublicationPublicView.action?institutionalItemId=14521&versionNumber=1); [IMSLP: Burgmüller Op. 100](https://imslp.org/wiki/25_%C3%89tudes_faciles_et_progressives%2C_Op.100_%28Burgm%C3%BCller%2C_Johann_Friedrich%29); [IMSLP: Bartók Mikrokosmos](https://imslp.org/wiki/Microcosmos_%28Bart%C3%B3k%2C_B%C3%A9la%29); [Universal Edition: Mikrokosmos](https://www.universaledition.com/en/Mikrokosmos/P0067322)
- **Question:** How could established piano methods become guided, rights-safe practice tracks in Easy Piano?

## Proposal

Add a **Methods** area to the app as a curated library of guided tracks. Each track follows a source work's progression while using Easy Piano's own lesson instructions, practice flow, feedback and progress tracking. The app should not be a PDF shelf: each study should be playable in short sections and connected to a clear skill goal.

Methods should complement the main course and remain optional. A learner can follow one book in order or use a recommended study to target a skill. The app can later recommend a starting point from placement results and demonstrated skills.

## Candidate catalog

| Work | Suggested role | Initial scope |
|---|---|---|
| Ferdinand Beyer, *Vorschule im Klavierspiel*, Op. 101 | Beginner progression for reading and coordination | Pilot candidate |
| Carl Czerny, Op. 599 | Progressive studies for coordination and fluency | Pilot candidate; start with a small sequence, not the full Czerny catalog |
| C. L. Hanon, *The Virtuoso Pianist* | Optional short technical routines | Supplementary track, with comfortable tempo guidance and breaks |
| Béla Bartók, *Mikrokosmos* | Progressive repertoire for reading, rhythm and varied musical language | Later addition after territory and edition review |
| Friedrich Burgmüller, *25 Études faciles et progressives*, Op. 100 | Graded musical studies between beginner and early-intermediate levels | Recommended first proof of content format |

Burgmüller's Op. 100 is especially suitable for a first slice: it is a compact, well-known sequence of musical studies, and a digitized historical edition is catalogued as public domain by the University of Rochester. Use a specific historical score source, and verify the license and provenance of the exact file before encoding or distributing it.

## Learner experience

1. **Browse Methods:** show author, title, level, focus skills, number of studies, source edition and supported regions.
2. **Choose a track:** offer a short explanation in original wording and recommend a starting study.
3. **Prepare:** show the score, listen to an app-produced or properly licensed reference performance, and set a comfortable tempo.
4. **Practice:** let the learner isolate a phrase, practice hands separately where useful, then play with the existing play-along feedback.
5. **Review:** save attempts, tempo and skill signals per study; suggest a retry or next study without hard-locking the learner.

## Content and implementation shape

- Represent a method as catalog metadata plus an ordered set of studies. A study points to the app's existing lesson/content format rather than embedding a publisher's page image.
- Add provenance per study: `source`, `source_url`, `arranger`, `license`, and `composition_license`, following the existing clean-room content rule.
- Write all explanations and practice prompts independently. Do not copy modern editorial notes, translations, fingering additions, audio, or page layout unless their rights are explicitly cleared.
- Prefer an original app engraving generated from verified public-domain notation data. Keep the original source citation and transcription review record alongside the content.
- Generate reference playback from the app's own notation renderer/synth, or use a recording with a separately verified license.
- Reuse the current notation parser and practice studio for score display, note checking, tempo changes and progress; implement a Methods catalog and track navigation only in a later approved product phase.

## Rights and distribution

Brazil's Law 9.610/1998, article 41, sets the general term for economic rights at 70 years from January 1 following the author's death. Under that general calculation, the underlying compositions by Beyer (d. 1863), Czerny (d. 1857), Hanon (d. 1900), Burgmüller (d. 1874), and Bartók (d. 1945) have passed that term in Brazil.

This is not enough to clear every asset or every market. The exact score edition, editorial additions, translation, arrangement, engraving, and recording can have separate rights. Bartók's *Mikrokosmos* remains protected in the United States until January 1, 2036 according to IMSLP; a worldwide app release therefore needs a territory-aware review or a distribution strategy that respects those restrictions. Preserve author attribution and check each selected source file before shipping.

This document is a product/content spike, not legal advice or approval to publish the scores.

## Recommended spike slice

Prototype one complete study from Burgmüller Op. 100 using a verified historical public-domain source:

- catalog entry and study metadata;
- original short teaching prompts and an identified skill goal;
- app-native score data and generated playback;
- phrase practice, play-along feedback and saved progress;
- source and license metadata validated by the existing content tooling.

If the existing content schema cannot express method/study ordering or provenance at the needed granularity, document the smallest schema extension before changing production content.

## Implications

- A Methods library can reuse core music and practice capabilities, but it needs a catalog and a durable progress model for studies.
- The learning value comes from sequencing and feedback authored by Easy Piano, not simply digitizing a book.
- Start with one small Burgmüller slice; add Beyer and Czerny next, Hanon as optional technique, and Bartók after territory-aware review.
- Do not begin app implementation or claim a new roadmap phase without the user's approval.

## Follow-ups

- Confirm the initial pilot method and target learner level.
- Review the existing content schema and progress store when implementation is approved.
- Validate the exact score files, editions, and intended distribution territories before adding content.
