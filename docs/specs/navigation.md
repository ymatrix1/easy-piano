# Navigation and URLs

The web app uses `go_router` so the address bar reflects the current destination and browser back/forward restores prior destinations.

| URL | Destination |
|---|---|
| `/learn` | Learn tab |
| `/practice` | Practice tab |
| `/profile` | Profile tab |
| `/course/<course-id>/node/<node-id>` | A course node and its task list |
| `/lesson/<level-id>` | A level, opened at its first stage |
| `/lesson/<level-id>?stage=<index>` | A level opened at a selected stage |
| `/practice/free-play` | Free play |
| `/practice/endless` | Endless practice setup |
| `/tools/midi` | MIDI developer spike |
| `/tools/staff` | Staff-rendering developer spike |

Tab changes replace the current tab location. Opening a course node, level or tool pushes a history entry; browser back returns to the previous screen. Course-node, lesson, and tool URLs can be bookmarked and opened directly. Lessons keep the selected stage in the `stage` query parameter.

Unknown paths redirect to `/learn`. Navigation state is in-memory; learner progress persistence is out of scope.
