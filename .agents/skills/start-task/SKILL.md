---
name: start-task
description: Start any Easy Piano task. Finds or creates the bean, makes a branch or worktree, writes the structured plan, reads the relevant docs.
---

# Start a task

1. `git fetch origin`.
2. Read the ROADMAP phase and every spec the task touches; check DECISIONS and OPEN-QUESTIONS.
3. `beans list --ready`. Create if missing: `beans create "Title" -t task -s in-progress --parent <epic> -d ...`; else `beans update <id> -s in-progress`.
4. Branch from `origin/main`: `git worktree add <path> -b <type>/<slug> origin/main`.
5. Bean body: Context ("Blocked by: none" if so), Higher Goal, Acceptance Criteria, Out of Scope, Summary of Changes (at end).
6. Once code exists, run the test suite before changing anything; note the baseline.
