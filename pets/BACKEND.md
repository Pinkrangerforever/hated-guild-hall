# Pet companion: backend handoff

For whoever has access to the guild's Supabase project. The front end is built and tested against a mock (`helpers/pet-api-mock.js`). This page says what the real database needs so the site can switch from the mock to it. The member-facing flow is in [FLOW.md](FLOW.md).

**The spec is the mock.** Each mock method is one RPC below, and `tests/pet-api-mock.test.mjs` lists every rule as a test. When this page and the mock disagree, the mock wins; tell us so we can fix this page.

## What exists today

- `shop_items` (with `category` and `metadata` jsonb) and `shop_purchases`.
- `purchase_shop_item(p_item_id)` returns `{ success, reason?, new_gold, item_name }`.
- `resolve_sparkle_event(p_pending_id, p_won)`: the three minigames end here.
- None of their SQL is in the repo, so the shapes above come from how `index.html` calls them.

## New tables

| Table | Columns | Notes |
| --- | --- | --- |
| `pets` | `id` uuid PK, `user_id`, `purchase_id` (unique, references `shop_purchases`), `egg_key` text, `monster_key` text, `skin` text null (null = normal art), `seed` bigint (0 to 2³²−1), `gen_version` int, `nickname` text, `total_xp` int default 0, `cosmetics` jsonb default `{}`, `hatched_at` | One row per hatched pet. |
| `pet_egg_actions` | `purchase_id`, `action_key`, `done_at`; PK (`purchase_id`, `action_key`) | Hatch actions ticked off per egg. A row is added only while that egg is active. |
| `pet_xp_log` | `pending_id` PK, `pet_id`, `amount`, `created_at` | One row per minigame, so a game pays XP once. |

On `profiles`:

| Column | Notes |
| --- | --- |
| `active_pet_id` uuid null, `active_egg_purchase_id` uuid null | The active companion. At most one is set (check constraint). |
| `pet_prefs` jsonb | `{ corner, visible, autoActivate, setupDone, sounds, eggShopFound }`. Defaults: `bottom-right`, true, false, false, true, false. |

**Row-level security:** members can read their own rows in all three tables. Every write goes through the `security definer` RPCs below, so there are no insert or update policies. (Later, a guild leaderboard would need `pets` readable by all members.)

## RPCs

Return `{ success: false, reason }` on a refusal, as `purchase_shop_item` does. The reasons below match the mock's error messages.

| RPC (mock method) | Does | Refuses with |
| --- | --- | --- |
| `purchase_pet_egg(p_item_id)` (`purchaseShopItem`, for eggs) | Charges gold and records the purchase, like `purchase_shop_item`. The egg becomes active if the member has no active companion, or has `autoActivate` on. Returns `becameActive`, `askToActivate`, `needsSetup` (= not `setupDone`). | `insufficient_gold`, `item_not_found`, `already_unhatched` (one unhatched copy at a time; buying again after it hatches is fine) |
| `record_site_action(p_action_key)` | If the active companion is an egg whose `hatch.actions` (in `shop_items.metadata`) include the key, adds a `pet_egg_actions` row. Returns that egg's `{ done, total, ready }`, or null. | `unknown_action` (allow-list = `pets/hatch-actions.json`) |
| `hatch_pet(p_purchase_id)` | Rolls the monster from `metadata.contents` by `chance`, then a skin from that monster's `skins` (null for the rest of 100%), picks a random `seed`, inserts the pet (nickname = the monster's name), and makes it the active companion. Skin chances come from `metadata.skins` (`{ monster_key: [{ key, chance }] }`). | `not_yours`, `already_hatched`, `not_active`, `not_ready` |
| `award_pet_xp(p_pending_id)` | For a resolved sparkle event of the caller's, adds 13 XP for a win or 5 for a loss to the active pet, once per event (`pet_xp_log`). The values are in `pets/xp.json`. Returns the new `total_xp`. | No active pet, or the active companion is an egg: `{ success: true, awarded: 0 }` |
| `set_active_companion(p_id)` | Sets the active pet or unhatched egg. | `not_yours` |
| `rename_pet(p_pet_id, p_nickname)` | Trims, collapses spaces, 1–24 characters. | `not_yours`, `bad_nickname` |
| `set_pet_prefs(p_prefs jsonb)` | Merges into `pet_prefs`, checking each field's type. | `bad_prefs` |

Not stored: level, traits and the XP bar. The client works them out from `total_xp`, `seed` and the egg's `xp_curve` with `helpers/generate-pet.js`.

## Data that ships with each egg

Each egg's `pets/eggs/<key>/shop_item.sql` inserts its `shop_items` row with `category = 'pet_egg'`. Its `metadata` carries `hatch`, `contents`, `xp_curve` and, when a monster has them, `skins`; the RPCs read these. Run each one once the RPCs exist; until then the site has no way to show or hatch the egg.

## Connecting the site

`index.html` gets a `pet-api-supabase.js` with the **same methods as the mock**, each calling one RPC through the existing `sb` client. It turns `{ success: false, reason }` into a thrown Error with a member-facing message, like the mock does. For example:

```js
async hatchPet(purchaseId) {
  const { data, error } = await sb.rpc('hatch_pet', { p_purchase_id: purchaseId });
  if (error || !data?.success) throw new Error(REASONS[data?.reason] || "Couldn't hatch the egg.");
  return data.pet;
}
```

Then the page code built in `sandbox.html` (purchase flow, overlay, hatch, Collection, sounds, throws) moves into `index.html`, with its `api` pointing at this module instead of the mock. See [DEPLOY.md](DEPLOY.md) for keeping the mock out of the live site.

## Order of work

1. Tables, RLS and RPCs in a migration, applied to a **separate dev Supabase project** first if possible (`supabase db dump` the schema from production to start it).
2. Run each egg's `shop_item.sql` there.
3. Point a local copy of the site at the dev project and repeat [TESTING.md](TESTING.md)'s checklist against the real backend.
4. Apply to production, then follow [DEPLOY.md](DEPLOY.md).
