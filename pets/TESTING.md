# Testing the pet companion

For reviewers. Everything here runs locally against a mock backend, so nothing touches the real site or database.

## Set up

```
git checkout feature/pet-companion
python pets/serve.py            # serves the repo at http://localhost:8080 with caching off
```

Open **http://localhost:8080/pets/sandbox.html**. If you've opened it before, press **Ctrl+Shift+R** once, then **Reset everything** in the Sandbox controls panel on the right.

The sandbox is a stand-in for the site: fake tabs (opening one counts as a hatch action), a Shop, minigame win and lose buttons, and the Collection. State is saved in your browser only.

**Sandbox controls:** +1,000 gold, Do every action, Reset everything, Fast idle (wobbles every 2–4 s instead of 12–20 s), Slow motion ×3, Throw now, and the next scheduled throw.

## Automated tests

```
node --test "pets/tests/*.test.mjs"
```

These cover the mock's rules (the spec for the real RPCs), pet generation, the throw schedule, the egg validator, and that every egg in the repo is complete. All should pass. Node 18 or later.

## Manual checklist

Follows [FLOW.md](FLOW.md). Tick as you go.

- [ ] **Hidden eggs (§1):** the Shop shows no Pet Eggs until you click GBUX at the bottom (hovering it shows the joke "credit card" tooltip); then they appear and stay after a reload.
- [ ] **Buy (§1):** Shop → Redeem on the Curious Egg → the confirm shows your gold before and after → the celebration says it's now your active companion.
- [ ] **Cancel:** Redeem → Cancel, Escape or a click outside leaves your gold unchanged.
- [ ] **First-time setup (§2):** after the first egg, "Meet your companion" appears; changing the corner moves the egg straight away.
- [ ] **Egg in the corner (§3):** hover only wobbles it; a click opens the checklist; visiting tabs plays a wobble with "n / 9".
- [ ] **Ready (§4):** after Do every action, a "!" badge appears; clicking the egg shows a Hatch button you can reach with the mouse.
- [ ] **Hatch (§5):** the egg moves to the center, wobbles twice, cracks, and a white flash reveals the Baby; the popup has only Nice!.
- [ ] **Pet in the corner (§6):** hover only rocks it; a click opens its panel; minigame wins float "+13 XP"; hovering an XP bar shows "n / 100 XP".
- [ ] **Second egg:** buy another → the popup asks "Make it your active companion?" with the "Always…" checkbox; Not now keeps the pet active and the egg shows as paused in the Collection.
- [ ] **Collection:** pets in list and grid views; a pet's card renames it (24 characters max) and has Make active; an egg row has Make active.
- [ ] **Companion settings:** corner, Show on every page (hiding keeps the companion active), Pet sounds, Always make new companions active.
- [ ] **Sound (§7):** with Pet sounds on, hear the unlock chime, ticks, the hatch crack and fanfare, the Baby's gorilla call (after hatching, on click at most every 3 s, and on level-up) and the throw whoosh; turning it off silences all of them.
- [ ] **Skins (§9):** in Sandbox controls, set Next hatch skin to "toon", then hatch: the Baby shows the drawn art everywhere (hatch, corner, Collection) with no special marking.
- [ ] **Easter egg (§8):** with the Baby active, Throw now sends a 🍌 or 🥕 across the page without blocking clicks.
- [ ] **Other Shop items:** buying Flame or Shadow uses the same confirm and celebration, and they show under Cosmetics.

Two quick looks at a single egg:
- `http://localhost:8080/pets/preview.html?egg=curious-egg`: the Shop card, animations, 20 sample hatches and the level table.
- `node pets/helpers/validate-egg.mjs curious-egg`: checks the files and prints the monster odds.

## Known gaps

- The real backend doesn't exist yet; see [BACKEND.md](BACKEND.md).
- Nothing is wired into `index.html` yet.
- Open in FLOW.md: whether Pet sounds is on by default, whether site sounds stay generated in code, and the proposed hidden Pet Eggs section.
