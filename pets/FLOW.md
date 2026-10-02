# Companion flow

How a member meets, hatches and keeps a pet companion. Status: **agreed 2026-10-01, built in mock mode**: try it in `pets/sandbox.html`. Rules live in `helpers/pet-api-mock.js`, with tests in `tests/pet-api-mock.test.mjs`.

## Rules

- **One active companion:** an egg or a pet. Only the active one makes progress: an egg ticks off hatch actions and can hatch only while active, and a pet earns minigame XP only while active.
- **Overlay:** the active companion sits in a corner of every page. Hiding the overlay doesn't change what's active; progress then shows only in the Collection.
- **Where settings live:** Collection → Companion settings. That covers the corner, show or hide the overlay, Pet sounds, and "Always make new companions active". It names the active companion; to change it, click a pet in the Collection and press **Make active** on its card, or use **Make active** on an egg's row.
- **"Always make new companions active":** off by default. When it's on, a new egg becomes active without asking. When it's off, every new egg prompts. The prompt has a checkbox that turns the setting on.
- **Size:** fixed by the site, not a member setting. Smaller on phones.

## 1. Buy an egg

Shop → Redeem → confirm the spend → unlock celebration (the site-standard flow for any Shop item).

- **Hidden Pet Eggs section:** the Shop's Pet Eggs section starts hidden. At the bottom of the Shop, "Find out how to get more gold" sits next to a joke button for a made-up payment app, **GBUX** ("★ 100% legit ★", gaudy neon, upright). Hovering it shows a plain little tooltip, styled as if a developer forgot to remove it: "click to link browser's stored credit card". Nothing is linked or collected; clicking just plays the chime and reveals the eggs. The reveal sticks for that member (`pet_prefs.eggShopFound`). GBUX is our own invention: never use a real app's name, colors or logo.
- **No active companion yet:** the egg becomes active by itself.
- **Already has one, setting off:** the celebration asks "Make the Curious Egg your active companion?" with Yes and Not now. Small print: *Only your active companion can hatch or earn XP.* Plus the "Always make new companions active" checkbox.
- **Already has one, setting on:** the egg becomes active with no prompt. The celebration says so.

## 2. First-time setup

Shown once, after the celebration for a member's first egg.

- A corner dropdown moves the egg live as it changes.
- Text: *You can change this any time in Collection → Companion settings: move your companion, switch which one is active, or hide it. A hidden companion stays active, and its progress shows in your Collection.*
- One button: Done.

## 3. Egg in the corner

- **Idle:** one wobble at a random interval of 12–20 seconds.
- **Hover:** a wobble, nothing else.
- **Click (or tap):** a wobble, and the progress panel opens: the hatch checklist with "n / total". Another click, or a click anywhere else, closes it.
- **Check-off:** a wobble and a floating "n / total" each time an action is ticked off.

## 4. Ready to hatch

- When the last action is done, a "!" alert badge pops onto the egg. Idle wobbles carry on, and nothing hatches by itself.
- Clicking the egg opens the panel with a **Hatch** button instead of the checklist, so hatching happens only when the member chooses to be there for it.

## 5. Hatch

1. A dimmed backdrop appears and the egg moves from its corner to the center of the screen.
2. Two wobbles, then a crack draws across the shell.
3. A white flash covers the egg. As it fades, the monster is there in the egg's place.
4. Congratulations popup: *"Baby has been added to your collection. Baby is now your active companion."* The only button is Nice!.
    - Only the active egg can hatch, so the new pet simply takes over its active slot. There's no prompt.
5. The backdrop closes and the overlay shows the new pet.

## 6. Pet in the corner

- No animation art for now. The idle is a gentle rock: a small tilt clockwise, then counter-clockwise, every 12–20 seconds.
- Hover rocks it, nothing else. A click rocks it and opens its panel: nickname, level with an XP bar, and a link to the Collection.
- Hovering any XP bar (in the corner, the panel or the Collection) grows it slightly and shows the fraction across it, such as "65 / 100 XP", in light bold text. At the hidden cap it shows total XP instead.
- Minigame XP floats "+13 XP", or "Level 2!" on a level-up.

## 7. Sound

The site has no sounds today, so this sets the standard. A shared helper (`pets/helpers/sfx.js`) plays every sound, with one master volume and a **Pet sounds** toggle in Companion settings that turns them all off. Browsers only allow sound once the member has clicked something on the page; before that, sounds are skipped silently.

| Moment | Sound | Kind |
| --- | --- | --- |
| Purchase celebration (any Shop item) | Short unlock chime | Site standard |
| Hatch action ticked off | Soft tick | Site standard |
| Hatch: crack, then flash | Crack, then a fanfare | Site standard |
| Pet revealed after the flash | The monster's call | Per monster |
| Pet clicked | The monster's call, at most once every 3 seconds | Per monster |
| Level up | The monster's call | Per monster |
| Easter egg: food thrown across the screen | A short whoosh | Site standard |

- **Per-monster call (optional):** `sounds.call` in monster.json (`src`, optional `volume` and `source`), under 100 KB. It's set while making the monster with `new-pet-monster`. A monster without one plays no call. A shared folder of sounds to pick from may come later.
- **Sourcing:** Wowhead NPC pages list each creature's sounds as `.ogg` files, the same way they expose model renders. It's Blizzard IP, the same caveat as the art. The Baby's call is "PetGorillaC" (1.3 s) from the [Baby Gorilla](https://www.wowhead.com/npc=269986/baby-gorilla) page, which uses the same model.

Open questions:
- [ ] Pet sounds on or off by default? (Proposed: on, at a quiet volume.)
- [ ] Site-standard sounds: generated in code, as the sandbox does now (no files), or real audio files, such as WoW UI sounds?

## 8. Easter egg: thrown food

Now and then the active pet "throws" something across the screen. A monster opts in by listing what it throws in monster.json: `throws`, a list of emoji (`{ "emoji": "🍌" }`) or images (`{ "src": "assets/carrot.webp" }`). The Baby throws a banana peel and a carrot.

- **Throw:** the pet rocks, then the item flies from it across the screen in a spinning arc and leaves the other side, in about 1.5 seconds. A whoosh plays if Pet sounds is on. It doesn't block clicks.
- **How often:** at most once in each quarter of the clock hour (:00–:14, :15–:29, :30–:44, :45–:59), so at most 4 an hour. Each quarter has about a 50% chance of a throw, at a random moment within it. Two can still land close together across a boundary, such as :14 and :16.
- **Remembered across pages:** the last quarter with a throw is saved in the browser, so a page reload can't cause a second throw in the same quarter.
- **Only when it makes sense:** the active companion is a pet with `throws`, the overlay is shown, and the browser tab is visible.

## 9. Skins

A monster can have alternate art, called skins. Hatching rolls the monster from the egg's contents, then rolls a skin from that monster's own list.

- **Only the art changes.** Name, type, rarity, traits, likes, call and default nickname stay the same.
- **No sign it's different:** no tag, no badge and no special reveal. The pet just looks different.
- **Defined per monster:** `skins` in monster.json, such as `[{ "key": "toon", "chance": 1, "animations": { "idle": { "src": "assets/skin-toon.webp" } } }]`. Chances are percentages; what's left over is the normal art. The odds are the same whichever egg hatches the monster.
- **Rolled once at hatch** by `hatch_pet` and stored on the pet (`pets.skin`, empty for the normal art), so it can't be re-rolled.
- **Making the art:** a new image (transparent background, square), a Wowhead model of the same creature, or a recolor with `helpers/make-art-variant.py`.
- **The Baby:** has a 1% hand-drawn skin.

## Decisions

- **2026-10-01:** One "Always make new companions active" setting. It skips the activate prompt, which otherwise appears for every new egg.
- **2026-10-01:** A hatched pet always takes over the egg's active slot. Hatching never prompts.
- **2026-10-01:** Overlay size isn't a member setting for now.
- **2026-10-02:** Panels open on click only, and hover just wobbles or rocks. A hover-opened panel closed as the mouse moved to its Hatch button, and a quieter hover looks better.
- **2026-10-02:** All companion sounds sit behind one **Pet sounds** setting that members can turn off.
- **2026-10-02:** A monster's call is optional and chosen in the `new-pet-monster` skill; no call means no sound.
- **2026-10-02:** No dropdown for the active companion; it got unwieldy with many pets. Make it active from the pet's card or the egg's row in the Collection.
- **2026-10-02:** The Collection's pet views are List and Grid ("Grid" replaced "Bubbles", a more common term).
- **2026-10-02:** Alternate monster art is called skins, rolled at hatch, with no visible sign that a pet has one.
- **2026-10-02:** The Pet Eggs section is hidden behind the GBUX joke button, and stays revealed once found (assumed; easy to switch to resetting each visit).
