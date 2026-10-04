# Going live without the test code

The site is static files, so whatever is in the repo gets published, including `pets/`. The test code can't touch the database on its own, but it shouldn't be loaded by the live site or left reachable as a page.

## What ships and what doesn't

| Ships (loaded by `index.html`) | Dev and test only (never loaded by `index.html`) |
| --- | --- |
| `helpers/generate-pet.js`, `egg-fx.js`, `shop-flow.js`, `sfx.js`, `throw-schedule.js`, `sprite.js` | `helpers/pet-api-mock.js`, the mock backend |
| `pet-api-supabase.js` (to be written; see [BACKEND.md](BACKEND.md)) | `sandbox.html`, `preview.html` |
| `eggs/index.json`, each `eggs/<key>/egg.json` and `assets/` | `tests/`, `serve.py`, `helpers/validate-egg.mjs`, `make-shop-art.py`, `make-art-variant.py`, `wowhead.py`, `remove-background.py` |
| `monsters/<key>/monster.json` and `assets/`, `traits.json`, `hatch-actions.json`, `xp.json` | Each egg's `shop_item.sql` (run once in Supabase, never served) and the `.md` docs |

**The rule that matters:** `index.html` must never load `pet-api-mock.js`, `sandbox.html` or `preview.html`. A test enforces it (`tests/catalog.test.mjs`), so run the tests before every deploy.

## Hiding the dev pages

They're harmless (they only ever use the mock and the browser's own storage), but they shouldn't be public pages. Before going live, pick one:

1. **Redirect them.** If the host reads a `_redirects` file (Netlify and Cloudflare Pages both do; the existing `_headers` file suggests one of them), add:
   ```
   /pets/sandbox.html   /   302
   /pets/preview.html   /   302
   ```
2. **Keep them out of the published branch.** Merge to the live branch without them, and keep testing on `feature/pet-companion`.

Check which host serves the site before choosing; this repo doesn't say.

## Go-live checklist

1. [ ] Backend applied to production (BACKEND.md), and each egg's `shop_item.sql` run.
2. [ ] `index.html` loads only the "Ships" files above, with `api` pointing at `pet-api-supabase.js`.
3. [ ] `node --test "pets/tests/*.test.mjs"` passes, including the check that `index.html` doesn't load mock or dev code.
4. [ ] Dev pages redirected or left out.
5. [ ] On the live site, signed in as a test member: buy an egg, hatch it, win a minigame, and check that a page reload keeps everything.
6. [ ] Rollback plan: setting an egg's `shop_items.active` to false shows it as Unavailable in the Shop (the site's existing behavior) without touching anyone's pets.
