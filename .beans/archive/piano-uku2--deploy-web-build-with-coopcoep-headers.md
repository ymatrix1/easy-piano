---
# piano-uku2
title: Deploy web build to Cloudflare Pages (COOP/COEP)
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:30Z
updated_at: 2026-10-16T19:08:59Z
parent: piano-eeut
---


## Context
Phase 1 (docs/ROADMAP.md). The web build needs COOP/COEP headers for the Rust/wasm core (flutter_rust_bridge); locally `tools/serve_web.py` sets them. GitHub Pages cannot set headers (only the coi-serviceworker workaround), so the user chose **Cloudflare Pages** (2026-10-16): native `_headers`, a preview URL per PR, global CDN, free. Blocked by: none (piano-dndu done).

## Higher Goal
First playable public web version (D9), plus a preview link on every PR for testing sound and visuals.

## Acceptance Criteria
- [x] GitHub Actions workflow: install Flutter + Rust/wasm toolchain, `python tools/sync_content.py`, `flutter_rust_bridge_codegen build-web --release`, `flutter build web --release`
- [x] Publishes `app/build/web` to Cloudflare Pages via `cloudflare/wrangler-action` (`pages deploy`); production on push to `main`, preview per PR, URL commented on the PR
- [x] `app/web/_headers` (copied into the build) sets `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, verified with `curl -I` on the deployed URL
- [x] SPA fallback so go_router deep links reload
- [x] Cache headers: long cache for hashed assets, no-cache for `index.html` and `flutter_service_worker.js`
- [x] Secrets documented: `CLOUDFLARE_API_TOKEN` (Pages edit scope), `CLOUDFLARE_ACCOUNT_ID`; the user creates the Pages project and adds the secrets
- [x] Smoke test on the preview URL: home loads (user, Chrome); lesson/MIDI on production to be rechecked after merge
- [x] Proposed decision D15 in docs/DECISIONS.md (hosting: Cloudflare Pages vs GitHub Pages), ARCHITECTURE deploy section, ROADMAP box ticked

## Out of Scope
Custom domain; mobile/desktop store builds; analytics; backend services.

## Summary of Changes
- `.github/workflows/deploy-web.yml`: Flutter + nightly Rust/wasm build, `wrangler pages deploy` (production on `main`, preview per PR with a PR comment; fork PRs build only).
- `app/web/_headers`: COOP/COEP/CORP, asset caching.
- D15 (proposed), ARCHITECTURE deploy section, ROADMAP box ticked. PR #17.
