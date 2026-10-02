---
name: new-pet-monster
description: Create a new monster (the pet that hatches from an egg) for the guild site's pet companion. Interviews the user for the monster's name, type, rarity, flavor text, likes and art, builds monster.json and its assets, and adds it to an egg's contents. Use when the user wants to add, design or change a monster or pet, or when new-pet-egg needs a monster that doesn't exist yet.
---

# New pet monster

You are adding one monster under `pets/monsters/`. Read `pets/README.md` first: it has the fields (monster.json) and **Getting art**. The member-facing flow is in `pets/FLOW.md`.

Before starting, read **Lessons from past cycles** at the end. They override anything above them.

**Called from `new-pet-egg`?** That skill already knows which egg and what chance. Skip step 5, return the monster key, and let it carry on.

## How to run it

- Ask in **rounds**, one per step, with numbered questions and a default in brackets for each.
- Write answers into the files after each round and show what you wrote in a line or two.
- Note any feedback on this skill as you go and apply it in step 7.

## Step 1: Basics

List the monsters that exist (name, type, rarity) for reference, then ask:
1. Default name. Owners can rename their pet. The key is derived from it: "Baby" → `baby`.
2. Type or family, for example Humanoid, Dragonkin, Beast or Elemental. List the types already used.
3. Rarity: common, uncommon, rare, epic or legendary. If you know the chance it will have in an egg, suggest one: under 5% is usually epic or legendary.
4. One line of flavor text.

Create `pets/monsters/<key>/assets/` and copy `templates/monster.json` into `pets/monsters/<key>/monster.json`.

## Step 2: Likes and personality

1. Its own likes list, or the shared one in `pets/traits.json`? [own] Each pet gets 2 or 3 likes and 1 dislike from it, so an own list needs at least 4 entries; 7 or 8 works well. Show the shared list for contrast.
2. Personality comes from the shared weighted list in `traits.json`. Only ask about an own list if the user brings it up. An own list must also total 100%.

## Step 3: Art, call and throws

Follow **Getting art** in `pets/README.md`. List the monster art already in the repo, then ask:
1. New art (a Wowhead link or a file), reuse another monster's art as it is, or a recolored copy? [new]
2. Any states beyond `idle`, such as `happy`, `sleep` or `levelup`? [idle only]
3. A call sound? It's optional [none]. It plays at hatch, on click and on level-up (FLOW.md §7). `python pets/helpers/wowhead.py npc <id>` lists the creature's sounds, numbered; prefer one about 1–2 seconds long. Save it with `--sound <n> --out pets/monsters/<key>/assets/call.ogg` (under 100 KB) and set `sounds.call`, with the NPC's page as `source`.
4. Any skins: alternate art a hatch can roll, such as 1% (FLOW.md §9)? [none] Art on a white background goes through `pets/helpers/remove-background.py`. If the art shows a real person, confirm they've agreed.
5. Does it throw anything across the screen now and then (the easter egg, FLOW.md §8)? List emoji or images [none]. The Baby throws 🍌 and 🥕.

## Step 4: Check

1. Show the user 6 sample rolls of this monster's traits (personality, likes and dislikes) with `generatePet` from `pets/helpers/generate-pet.js`, so they can judge the likes list.
2. A monster is validated through the eggs that hatch it, so the full check comes in step 6.

## Step 5: Which egg hatches it

Every monster must be hatched by at least one egg; the tests fail on an unused monster folder. Ask:
1. Add it to an existing egg, or make a new egg for it? Make a new egg with `new-pet-egg`, which then picks this monster.
2. For an existing egg, show its current contents and chances, then ask for this monster's chance and how to rebalance the others so the total is still 100%.

If the egg is already live (its `shop_item.sql` has been run), follow the egg skill's **Rules for eggs that are already live**.

## Step 6: Check and commit

1. Run `node pets/helpers/validate-egg.mjs <egg-key>` for each egg that hatches it, then `--sql` to refresh that egg's `shop_item.sql`.
2. Run `node --test "pets/tests/*.test.mjs"`. Never commit while it fails.
3. Point the user to `http://localhost:8080/pets/preview.html?egg=<egg-key>` to see the monster in sample hatches, and to the sandbox to hatch it.
4. Ask before committing, on the current feature branch, with a message like `Add <Name> pet monster`.

## Step 7: Feedback on this skill

Ask: "Anything about this process to change for next time?" Edit the affected step, or add a dated line to **Lessons** below. Show the diff.

## Rules for monsters that are already live

Once any member may have hatched it:
- Never rename the key or delete the folder. Pets point to it by `monster_key`.
- Only append to its likes or personality lists. Removing or reordering entries changes existing pets' traits.
- Name, flavor text and art can change freely.

## Lessons from past cycles

Newest first. Format: `- YYYY-MM-DD: what to do differently, and why.`

- 2026-10-01: Split out of `new-pet-egg`, because monsters vary much more than eggs. Lessons below came from the egg skill.
- 2026-10-01: A single still image is fine for a monster for now. Real animation is wanted later. Don't press for sprite strips.
- 2026-09-30: A monster's likes are usually its own list (the Baby has 7), not the shared guild-themed one.
- 2026-09-30: The user often types in lowercase without punctuation. Write names in Title Case and flavor text as a normal sentence, without asking.
