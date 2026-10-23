# Navigation and URLs

The web app uses `go_router` so the address bar reflects the current destination and browser back/forward restores prior destinations.

| URL | Destination |
|---|---|
| `/learn` | Learn tab |
| `/practice` | Practice tab |
| `/profile` | Profile tab |
| `/lesson/<level-id>` | A level, opened at its first stage |
| `/tool` | An in-session developer or practice tool; requires router state |

Tab changes replace the current tab location. Opening a level or tool pushes a history entry; browser back returns to the previous screen. Lesson URLs can be bookmarked and opened directly. `/tool` is transient and falls back to Learn when loaded without its in-session destination.

Unknown paths redirect to `/learn`. Navigation state is in-memory; learner progress persistence is out of scope.
