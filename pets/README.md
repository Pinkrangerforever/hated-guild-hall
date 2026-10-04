# Pets

Everything for the pet companion lives here: one folder per egg, one folder per monster, and the shared helpers.
Docs: [FLOW.md](FLOW.md) is the member-facing flow, [TESTING.md](TESTING.md) is how to review it in mock mode, [BACKEND.md](BACKEND.md) is the Supabase handoff, and [DEPLOY.md](DEPLOY.md) covers going live without the test code.
To add an egg, use the `new-pet-egg` skill; to add a monster, use `new-pet-monster` (both in `.claude/skills/`). The egg skill hands off to the monster skill when an egg needs a new monster.

```
pets/
  README.md              this file: layout and field reference
  traits.json            shared personalities (weighted, chances total 100) and likes
  hatch-actions.json     site actions an egg can ask for, with their player-facing wording
  xp.json                XP per minigame win and loss, the same for every egg
  preview.html           browser preview of one egg: ?egg=<egg-key>
  sandbox.html           mock-mode stand-in for the site: buy, check off, hatch, minigame XP, Collection
  helpers/
    generate-pet.js      seeded random, monster roll, trait generation, levels (no DOM)
    sprite.js            draws an animation entry (image, GIF or sprite strip)
    egg-fx.js            site-standard egg animations: check-off wobble, ready loop, hatch
    shop-flow.js         site-standard Shop purchase: confirm the spend, then the unlock celebration
    sfx.js               every companion sound, behind the Pet sounds setting
    throw-schedule.js    when the thrown-food easter egg fires (at most once per quarter-hour)
    pet-api-mock.js      in-browser stand-in for the pet RPCs; the spec for the real ones
    validate-egg.mjs     checks an egg and its monsters, and writes its shop SQL
    make-shop-art.py     builds an egg's Shop card banner from its idle art (needs Pillow)
    make-art-variant.py  recolors existing art (hue, saturation, tint) so reused art looks new
    wowhead.py           finds a creature on Wowhead and downloads its model image and sounds
    remove-background.py makes art on a white background transparent, square and WebP
  tests/                 node --test suite: every egg in eggs/ must pass, no unused monsters
  eggs/index.json        every egg key, in Shop order (the sandbox reads it)
  eggs/<egg-key>/
    egg.json
    assets/              egg art, plus shop.webp (the Shop card banner)
    shop_item.sql        generated, never edited by hand
  monsters/<monster-key>/
    monster.json
    assets/              monster art
```

Monsters live outside the egg folders so one monster can appear in several eggs.

## How a pet comes to be

1. A member buys the egg in the Shop. That is an ordinary `shop_items` row with `category = 'pet_egg'`.
2. The egg sits in the overlay until the member has done `hatch.distinct_actions` of the listed actions.
3. The member clicks to hatch it. `hatch_pet` rolls the monster from the egg's `contents`, then stores `monster_key` and a random `seed` on the pet.
4. The client works out the cosmetic traits from `seed` with `generatePet`, and the level from total XP with `levelForXp`.

Because `monster_key` is stored, changing an egg's chances only affects future hatches.
The traits are recomputed from the seed, so editing `traits.json` changes existing pets. Only append to those lists, or bump `GEN_VERSION`.

## egg.json

| Field | Required | Meaning |
| --- | --- | --- |
| `key` | yes | Same as the folder name, lowercase-with-dashes. |
| `name` | yes | Shown in the Shop and the overlay. |
| `description` | yes | One or two sentences for the Shop card. |
| `price` | yes | Cost in guild gold. |
| `shop_image` | yes | Shop card banner, about 3:1 (480×160 is ideal). Made by `helpers/make-shop-art.py`. |
| `animations.idle` | yes | The egg sitting in the overlay. |
| `animations.ready` | no | Plays once the hatch conditions are met (wobble). |
| `animations.hatch` | no | Plays once when the egg is clicked open. |
| `hatch.actions` | yes | Keys from `hatch-actions.json` that count toward hatching. |
| `hatch.distinct_actions` | yes | How many different listed actions are needed. |
| `contents` | yes | `[{ "monster": "<monster-key>", "chance": 70 }, …]`. Chances are percentages and must total 100. |
| `xp_curve` | yes | XP needed for each level-up, in order. Six entries means the hidden cap is level 7. |

## monster.json

| Field | Required | Meaning |
| --- | --- | --- |
| `key` | yes | Same as the folder name. |
| `name` | yes | Default pet name. Owners can rename their pet. |
| `type` | yes | Family shown on the pet, for example Dragonkin. |
| `rarity` | yes | `common`, `uncommon`, `rare`, `epic` or `legendary`. |
| `description` | yes | One line of flavor text. |
| `animations.idle` | yes | The pet's default loop. |
| `animations.<state>` | no | Other states, for example `happy`, `sleep` or `levelup`. |
| `throws` | no | Easter egg (FLOW.md §8): what the pet throws across the screen, as `[{ "emoji": "🍌" }, { "src": "assets/carrot.webp" }]`. |
| `sounds.call` | no | The monster's call (FLOW.md §7): `{ "src": "assets/call.ogg", "volume": 0.6, "source": "…" }`, under 100 KB. |
| `skins` | no | Alternate art (FLOW.md §9): `[{ "key": "toon", "chance": 1, "animations": { "idle": { "src": "assets/skin-toon.webp" } } }]`. Chances are percentages, under 100 in total. |
| `traits.personality`, `traits.likes` | no | Replace the shared lists in `traits.json` for this monster only. Same format: `personality` is `[{ "name": "Brave", "chance": 6 }, …]` totalling 100, `likes` is a plain list of at least 4; each pet gets 2 or 3 likes and 1 dislike from it. |

## Animations

Each animation entry is `{ "src": "assets/idle.png", "frames": 4, "fps": 6, "frame_width": 64, "frame_height": 64 }`.

- **Single image or GIF:** leave out `frames` (or set it to 1). A GIF plays its own animation.
- **Sprite strip:** one PNG with all frames side by side, left to right, each `frame_width` × `frame_height` pixels. Set `frames` and `fps`.
- Transparent backgrounds, square frames, 64 or 128 px per frame. Keep each file under 500 KB, since the overlay is on every page.
- File names describe the state: `idle.png`, `ready.png`, `hatch.png`, `happy.png`. WebP is preferred for stills; it's much smaller.
- Optional `"source"` on an entry records where the art came from, such as a Wowhead page.
- `src` may point into another egg's or monster's folder (`../curious-egg/assets/idle.webp`) to reuse art without copying it. The tests fail if that file goes away.

## Roadmap

1. [x] **Review the flow:** settle the open questions in [FLOW.md](FLOW.md).
2. [x] **Build it in mock mode:** `sandbox.html` and `helpers/pet-api-mock.js` follow FLOW.md, with a test for every rule.
3. [x] **Backend handoff:** [BACKEND.md](BACKEND.md) covers the tables, row-level security, each RPC's rules and refusals, and how the site connects. Still to write: the SQL migration itself, best done by whoever applies it.
4. [ ] **Wire into the site:** `index.html` calls a real API module with the same methods as the mock. This can run alongside step 3 against the mock, and switches over when the backend lands.
5. [ ] **Launch:** follow the go-live checklist in [DEPLOY.md](DEPLOY.md).

## Mock mode

The real backend (the `pets` and `site_actions` tables, and RPCs such as `hatch_pet`) doesn't exist yet, and the live site uses the production database.
Until then, `pets/sandbox.html` runs the whole pet flow against `helpers/pet-api-mock.js`, saving state in your browser only:

```
python pets/serve.py        # from the repo root
# open http://localhost:8080/pets/sandbox.html
```

It follows [FLOW.md](FLOW.md): buy an egg (confirm, celebrate, make it active, first-time setup), tick off actions, hatch it from the corner panel, and manage companions in Collection → Companion settings.
Two sample name customizations show the purchase flow works for any Shop item. Win or lose minigames to give XP to the active pet.
The Sandbox controls panel has extra gold, "Do every action", fast idle wobbles (2–4 s instead of 12–20 s), slow motion, sound, overlay size and a reset.
Each method in the mock applies the rules its real RPC must enforce, and `tests/pet-api-mock.test.mjs` pins those rules down.

## Getting art

Both skills (`new-pet-egg`, `new-pet-monster`) follow this.

- **Three sources:** new art, reuse another egg's or monster's file as it is (point `src` at it, such as `../curious-egg/assets/idle.webp`; don't copy it), or a recolored copy made with `helpers/make-art-variant.py`. For the copy, render the options with `--sheet`, let the user pick a hue, then write it with `--hue` (fine-tune with `--sat`, `--bright` or `--tint`).
- **Wowhead:** use `helpers/wowhead.py`.
  ```
  python pets/helpers/wowhead.py search "baby gorilla"           # find the NPC id
  python pets/helpers/wowhead.py npc 269986                      # its model, image link and numbered sounds
  python pets/helpers/wowhead.py npc 269986 --image <folder>/assets/idle.webp --sound 1 --out <folder>/assets/call.ogg
  python pets/helpers/wowhead.py image 80256 <folder>/assets/idle.webp   # by model display ID or webthumbs URL
  ```
  The image is the model's 300×300 still render, cropped and squared; the script warns if the model runs off its edges. Many NPCs share a model, so any NPC with the right model works as a source of sounds.
- **Art on a white background** (drawings, AI art): `python pets/helpers/remove-background.py <in> <out.webp>`. If a drop shadow survives, lower `--min-light` (135 worked for the Baby's skin) or keep it faint with `--keep-shadow`. Look at the result on a dark background before using it.
- **Art of a real person:** get their OK first, and record it in `"source"`. The repo is public.
- **Pasted images aren't saved to disk.** Ask for a Wowhead link or a file path instead.
- Save files in the right `assets/` folder, named after their state. Never hotlink.
- Check each image with the Read tool: transparent background, and for a strip, the frame count matches the width.
- Record where each file came from in its entry's `"source"` (a URL, "recolored from curious-egg, --hue 90", or "drawn by <name>").
- A single still is fine for now; motion comes from the site-standard wobble and rock.

## Checking an egg

```
node --test "pets/tests/*.test.mjs"                   # every egg and monster fully built, plus helper tests
node pets/helpers/validate-egg.mjs <egg-key>          # check one egg's files and print the roll odds
node pets/helpers/validate-egg.mjs <egg-key> --sql    # also write eggs/<egg-key>/shop_item.sql
python pets/serve.py                            # from the repo root, then open
                                                      # http://localhost:8080/pets/preview.html?egg=<egg-key>
```
