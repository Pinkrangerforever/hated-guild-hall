---
name: new-pet-egg
description: Create a new pet egg for the guild site's pet companion. Interviews the user for the egg's name, price, art and Shop card, hatch conditions and contents (which monsters it can hatch and at what % chance, picking existing monsters or handing off to new-pet-monster), then validates, previews and writes the shop SQL. Use when the user wants to add, design or change a pet egg.
---

# New pet egg

You are adding one egg under `pets/eggs/`. Read `pets/README.md` first: it has the folder layout, every field and **Getting art**. This file is the process. Monsters have their own skill, `new-pet-monster`.

Before starting, read **Lessons from past cycles** at the end. Those are the user's corrections from earlier runs, and they override anything above them.

## How to run it

- Ask in **rounds**, one round per step below, and number the questions so the user can answer "1. …, 2. …".
- After each round, write the answers into the files straight away, then show what you wrote in one or two lines. Don't save everything for the end.
- Offer a default for every question, in brackets, so "default" or a blank answer is a valid reply. Use defaults from existing eggs where there are some.
- The user may give feedback on this skill at any point ("next time ask X first", "don't ask about Y"). Note it, carry on, and apply it in step 8.
- If the user already answered something in their request, don't ask it again.

## Step 1: The egg

Ask:
1. Egg name, as shown in the Shop. The key is derived from it: "Hatchling Egg" → `hatchling-egg`.
2. Shop description, one or two sentences.
3. Price in gold. List existing egg prices for reference, and note that Name Customizations cost about 2,500.

Then create the folders, copy the template, and add the key to the egg list:
```
pets/eggs/<egg-key>/assets/
pets/eggs/<egg-key>/egg.json      ← from templates/egg.json
pets/eggs/index.json              ← append "<egg-key>"; the sandbox and Shop order read it
```

## Step 2: Egg art and Shop card

List the egg art already in the repo (`pets/eggs/*/assets/idle.*`), then ask:
1. Where does this egg's art come from? [a recolored copy of the most recent egg]
    - New art, reuse another egg's as it is, or a **recolored copy (usual)**. Follow **Getting art** in `pets/README.md`; for new art from Wowhead, use `pets/helpers/wowhead.py`. For a copy, show the hue sheet with the Read tool and let the user pick.
2. Shop card: the standard banner (the egg's art on the site's warm brown-and-gold glow), or a custom background image? [standard]

The Shop shows each egg as a card with an image strip 80px tall and 150–260px wide, cropped to fill. A square egg image would lose its top and bottom, so every egg needs a wide `shop_image`: 3:1, ideally 480×160, with the egg in the middle third. Run `python pets/helpers/make-shop-art.py <egg-key>`, adding `--bg <image>` for a custom background. It writes `assets/shop.webp` and sets `shop_image`. Look at the result with the Read tool. The card's text comes from step 1.

## Step 3: Hatch conditions

Show the actions in `pets/hatch-actions.json` as a numbered list, then ask:
1. Which actions count toward hatching? [all of them]
2. How many different ones are needed? [all the listed ones]

If the user wants an action that isn't in the list, add it to `hatch-actions.json` with player-facing wording. Also tell them it needs code: a `record_site_action('<key>')` call where it happens in `index.html`, plus the key in the server's allow-list.

## Step 4: Contents

List the existing monsters with their type, rarity and art, then ask:
1. Which monsters can hatch from this egg, and what % chance does each have? The chances must total 100. Pick existing ones, or say "new" for a monster that doesn't exist yet.

For each "new" one, run the `new-pet-monster` skill, telling it this egg and chance, so it skips its egg step. Then come back here.

Before moving on, check the total out loud ("70 + 25 + 5 = 100").

## Step 5: XP curve

Show the curve from the most recent egg; the first egg used `[60, 100, 140, 180, 230, 290]`, which is 1,000 XP to level 7. XP per minigame is the same for every egg and lives in `pets/xp.json` (13 for a win, 5 for a loss). With those values, 1,000 XP takes 77 games if every one is won, about 112 at a 50% win rate, and 200 if every one is lost. Show the user that range for the curve they choose. Ask whether to keep it. The number of entries sets the hidden level cap, at entries + 1.

## Step 6: Check and preview

1. Run `node pets/helpers/validate-egg.mjs <egg-key>`, fix every error, and show the user any warnings. It's fine to run this after any earlier round to show what's still missing.
2. Show the odds table it prints, set % against rolled %.
3. Start `python pets/serve.py` from the repo root in the background, and give the user `http://localhost:8080/pets/preview.html?egg=<egg-key>`. Ask them to check the Shop card at both widths, that the animations play correctly, and that the sample pets look right.
4. Then point them to `http://localhost:8080/pets/sandbox.html` to try the egg end to end in mock mode: buy it, tick off its actions, watch the wobble and the hatch, and see the pet in the Collection. "Reset everything" in the Sandbox controls starts over.

## Step 7: Shop SQL and commit

1. Run `node pets/helpers/validate-egg.mjs <egg-key> --sql` to write `pets/eggs/<egg-key>/shop_item.sql`.
2. Tell the user the SQL has **not** been run. Someone with Supabase access has to apply it, as with `add_newworld_item.sql`.
3. Run the full suite: `node --test "pets/tests/*.test.mjs"`. It fails if any egg or any monster it hatches is incomplete, if `shop_item.sql` is out of date, or if a monster folder isn't used by any egg. Never commit while it fails. Show the user the pass/fail counts.
4. Ask before committing. If they agree, commit on the current feature branch, never `main`, with a message like `Add <Egg Name> pet egg`.

## Step 8: Feedback on this skill

Ask: "Anything about this process to change for next time?" Then, with what they said here and anything they said along the way:
- A change to a step: edit that step directly.
- A preference or a pitfall: add a dated line to **Lessons from past cycles** below.
- Show the user the diff of this file.

## Rules for eggs that are already live

These apply once an egg's SQL has been run and members may own it.
- Changing chances or adding monsters only affects future hatches, so it's safe. Regenerate the SQL as an `UPDATE` and say so.
- Never remove a monster from an egg that members may already have hatched it from. For monster-level rules, see `new-pet-monster`.
- Only append to `pets/traits.json`. Removing or reordering entries changes the traits of pets that already exist.

## Lessons from past cycles

Newest first. Format: `- YYYY-MM-DD: what to do differently, and why.`

- 2026-10-01: Monsters moved to their own skill, `new-pet-monster`, because they vary much more than eggs. Step 4 picks existing monsters or hands off.
- 2026-10-01: Ask about egg art and the Shop card right after the egg's name and price (step 2), not after the monsters. Eggs will often reuse an earlier egg's art as a recolored copy, with a new name such as "Gorilla Egg".
- 2026-10-01: Every egg needs Shop card art. It was missing from the first version of this skill.
- 2026-09-30: Check-off feedback (wobble plus an "n / total" fraction) is one site standard, not per egg. Don't ask about it per egg.
- 2026-09-30: Every egg and the monsters it references must be fully built before committing, enforced by `pets/tests/`. When the validator gains a new check, add a matching "catches …" case to `pets/tests/validator.test.mjs`.
- 2026-09-30: The user often types in lowercase without punctuation. Write names in Title Case and descriptions as normal sentences, without asking ("curious egg" → "Curious Egg").
- 2026-09-30: The user values tests. Whenever a helper changes, re-run the validator on a good egg and on a deliberately broken copy, and say what was checked.
