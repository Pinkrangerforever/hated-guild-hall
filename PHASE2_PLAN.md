# Phase 2: Pet System Implementation

## What We've Completed (Phase 0 & 1)

✅ **Phase 0 - Database Foundation**
- All tables created: pets, house, house_additions, mystery_trader_access
- Columns added: food, wood (profiles table)
- Shop categories expanded
- RLS policies in place
- All RPC functions created with server-side verification (can't be hacked by client)

✅ **Phase 1 - Mystery Trader & Unlock System**
- Secret /dealer page with shadowy NPC
- Sequential footprint trail animation (visibility logic perfected)
- 3000g payment trigger → Sets mystery_trader_access
- Server-verified access control (RPC checks database, not just client)
- Footprints only show when: logged in + no access + not on entry/dealer pages
- Ready for pet eggs to appear in shop

---

## Phase 2: Pet System (4-6 hours)

### What to Build

#### 1. **Pet Egg Purchase & Display**
- Show "Pet Eggs" category in shop (only visible if user has mystery_trader_access)
- Egg types: Dragon, Phoenix, Gryphon (or similar)
- Costs: 500-1000g per egg
- When purchased: Creates pet record with status='egg', hatch_time=now+24hrs

#### 2. **Egg Hatching (24-hour countdown)**
- **Client-side timer**: localStorage countdown (shows "12h 34m remaining")
- **Server validation**: On page load, check if hatch_time has passed
- **Hatching trigger**: Either auto-hatch when timer ends OR click "Hatch" button
- **On hatch success**: 
  - Update pet.status = 'juvenile'
  - Show naming modal

#### 3. **Pet Naming Modal**
- Appears when egg hatches
- Input field (max 30 characters)
- Call `name_pet` RPC on submit
- Update state.profile.pets

#### 4. **Pet Frame UI**
- **Pet Card Layout**:
  - Pet model/image (WoW viewer embed or static image)
  - Pet name (from pet.name)
  - Level display (e.g., "Level 3")
  - EXP bar (current_exp / required_exp)
  - Three buttons below: [Pet Button] [Feed] [Info]

#### 5. **Pet Leveling System**
- **EXP Requirements** (cumulative):
  - L1→L2: 100 total EXP
  - L2→L3: 250 total EXP
  - L3→L4: 450 total EXP
  - L4→L5: 700 total EXP
  - (increases by ~100-150 per level)

- **Evolution Stages**:
  - L1-L4: "Juvenile" (smaller model)
  - L5-L9: "Adult" (medium model)
  - L10+: "Boss" (large model)

- **Client-side calculation**: Math for level-up is client-safe
- **Server validation**: On level-up, RPC validates total EXP

#### 6. **Pet Buttons (1-hour cooldown)**
- **"Pet Button"** (e.g., "Pet", "Poke", "Play")
  - Cost: 0 resources
  - Reward: 3 EXP
  - Cooldown: 1 hour
  - localStorage tracks last_pet_action_time (validate on click)
  - RPC: `pet_action(user_id, pet_id)` → awards EXP, updates cooldown

#### 7. **Feed Button**
- **"Feed Pet"**
  - Cost: 1 Food resource
  - Reward: 5 EXP
  - No cooldown (can spam-feed)
  - RPC: `feed_pet(user_id, pet_id)` → deducts food, awards EXP

#### 8. **Pet Persistence**
- **On page load**:
  - Fetch user's pets from DB
  - Check hatch timers (are any ready to hatch?)
  - Validate cooldowns (are they still active?)
  - Load into state.profile.pets

- **Data sync strategy**:
  - Client tracks: timers, visual state, cooldown countdown
  - Sync to DB only on: feed, level-up, name, hatch completion
  - Validate all actions server-side (RPC functions)

---

## Implementation Order

1. **Add eggs to shop** (30 min)
   - Add pet egg items to shop_items table
   - Show in UI with correct category
   - Purchase flow → creates pet record

2. **Hatching countdown** (45 min)
   - localStorage timer on pet card
   - "Hatch now" button when timer expires
   - Call `hatch_egg` RPC

3. **Pet naming modal** (30 min)
   - Modal form on hatch completion
   - Input validation (1-30 chars)
   - Call `name_pet` RPC

4. **Pet frame & display** (1 hour)
   - Pet card UI with model placeholder
   - Level/EXP display
   - Buttons: [Pet Button] [Feed]

5. **Leveling logic** (1 hour)
   - Client-side EXP calculation
   - Level-up detection
   - Evolution stage switching (L1-4 vs L5-9 vs L10+)

6. **Button cooldowns** (1 hour)
   - localStorage cooldown tracking
   - Pet button (1hr cooldown) → RPC `pet_action`
   - Feed button (no cooldown) → RPC `feed_pet`
   - Validate cooldowns server-side

---

## Key Security Notes

✅ **All dangerous operations server-verified**:
- `feed_pet` RPC: Checks food balance before deducting
- `pet_action` RPC: Validates 1-hour cooldown server-side
- `hatch_egg` RPC: Validates 24-hour timer server-side
- `name_pet` RPC: Validates pet ownership + name length

⚠️ **Client-side optimizations are safe**:
- Timer countdown: Just for UI, validated server-side on hatch
- Cooldown display: Just UI countdown, validated on next action
- EXP math: Client calculates level, server validates on RPC

---

## Files to Modify

- `index.html`:
  - Add pet shop items section
  - Add pet card UI component
  - Add hatching countdown timer
  - Add pet naming modal
  - Add pet button cooldown logic
  - Add feed button logic

- Database (via migrations):
  - Ensure pet egg shop_items exist (may need to add if not there)
  - Verify all RPCs are accessible

---

## Testing Checklist

- [ ] Buy pet egg → pet created with status='egg'
- [ ] 24-hour countdown shows correctly
- [ ] Click "Hatch" at 0:00 → hatch modal appears
- [ ] Name pet → pet.name updates
- [ ] Pet button with 1hr cooldown works → EXP awarded
- [ ] Feed button works → EXP + food deducted
- [ ] Page reload → timers/cooldowns persist correctly
- [ ] Level-up triggers → evolution stage changes (if implemented)
- [ ] Can't double-click buttons → server validation prevents cheating

---

## Timeline Estimate

- Eggs in shop: 30 min
- Hatching: 45 min
- Naming: 30 min
- Pet UI: 1 hour
- Leveling: 1 hour
- Buttons & cooldowns: 1 hour

**Total: 4-5 hours**

Ready to start? 🐣
