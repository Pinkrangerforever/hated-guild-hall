-- Migration: WoW trivia mini-game (rune book) + 143-question bank
-- Purpose:
--   * trivia_questions: question, 4 answers (jsonb, correct one at correct_index), category, difficulty.
--     Players can't read it (RLS on, no grants); the Raid Leader edits it in the SQL editor.
--   * pending_games.secret: per-game data the browser must never see (trivia's correct option).
--   * claim_sparkle_gold: 15% of sparkles are now trivia (fishing/blacksmith/murloc 20% each, plain 25%).
--     Picks a question the player hasn't had in their last 40, shuffles the answers every time.
--   * resolve_sparkle_event: checks the chosen option against the secret; under 0.9 s is flagged.
--     Trivia pays 20-35 gold (Weary applies), no food.
-- Date: 2026-10-11
-- Reverse: re-run claim_sparkle_gold / resolve_sparkle_event from 20261011000900; drop trivia_questions,
--          pending_games.secret, and 'trivia' from the two event-type checks.

CREATE TABLE IF NOT EXISTS public.trivia_questions (
  id SERIAL PRIMARY KEY,
  category TEXT NOT NULL,
  difficulty INTEGER NOT NULL DEFAULT 1,
  question TEXT NOT NULL UNIQUE,
  answers JSONB NOT NULL,          -- exactly 4 strings
  correct_index INTEGER NOT NULL,  -- 0-3, position of the right answer in "answers"
  active BOOLEAN NOT NULL DEFAULT true,
  CHECK (jsonb_array_length(answers) = 4 AND correct_index BETWEEN 0 AND 3)
);
ALTER TABLE public.trivia_questions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.trivia_questions FROM anon, authenticated;

INSERT INTO public.trivia_questions (category, difficulty, question, answers, correct_index) VALUES
  ('Classes', 1, 'Which class can tame beasts as permanent companions?', '["Hunter", "Warlock", "Druid", "Shaman"]'::jsonb, 0),
  ('Classes', 1, 'What resource do Rogues spend on their abilities?', '["Energy", "Rage", "Mana", "Focus"]'::jsonb, 0),
  ('Classes', 1, 'What resource do Warriors build up by dealing and taking damage?', '["Rage", "Energy", "Mana", "Combo Points"]'::jsonb, 0),
  ('Classes', 1, 'Which class can come back to life on its own with Reincarnation?', '["Shaman", "Paladin", "Priest", "Druid"]'::jsonb, 0),
  ('Classes', 1, 'Which class conjures food and water?', '["Mage", "Priest", "Warlock", "Druid"]'::jsonb, 0),
  ('Classes', 1, 'Which class can create Healthstones?', '["Warlock", "Priest", "Mage", "Paladin"]'::jsonb, 0),
  ('Classes', 1, 'Which spell turns an enemy into a harmless sheep?', '["Polymorph", "Hex", "Hibernate", "Banish"]'::jsonb, 0),
  ('Classes', 1, 'Which Druid form is used for tanking?', '["Bear Form", "Cat Form", "Moonkin Form", "Travel Form"]'::jsonb, 0),
  ('Classes', 1, 'Which class has Feign Death?', '["Hunter", "Rogue", "Priest", "Warrior"]'::jsonb, 0),
  ('Classes', 1, 'Which class can Mind Control an enemy?', '["Priest", "Warlock", "Mage", "Shaman"]'::jsonb, 0),
  ('Classes', 1, 'What does a Shaman place on the ground to aid their party?', '["Totems", "Runes", "Wards", "Banners"]'::jsonb, 0),
  ('Classes', 2, 'Which Paladin spell makes them immune to all damage for a short time?', '["Divine Shield", "Lay on Hands", "Blessing of Freedom", "Divine Intervention"]'::jsonb, 0),
  ('Classes', 2, 'Which Warlock demon is the classic tanking pet?', '["Voidwalker", "Imp", "Succubus", "Felhunter"]'::jsonb, 0),
  ('Classes', 2, 'Which class can summon a Felsteed as a mount?', '["Warlock", "Paladin", "Death Knight", "Shaman"]'::jsonb, 0),
  ('Classes', 2, 'In Classic, which of these classes can only wear leather or cloth armor?', '["Rogue", "Hunter", "Shaman", "Paladin"]'::jsonb, 0),
  ('Classes', 2, 'Which Druid spell can resurrect an ally during combat?', '["Rebirth", "Revive", "Tranquility", "Innervate"]'::jsonb, 0),
  ('Classes', 1, 'Which class uses Cheap Shot to stun from stealth?', '["Rogue", "Druid", "Warrior", "Hunter"]'::jsonb, 0),
  ('Classes', 2, 'Mortal Strike is found in which Warrior talent tree?', '["Arms", "Fury", "Protection", "Discipline"]'::jsonb, 0),
  ('Classes', 2, 'Shadowform belongs to which Priest talent tree?', '["Shadow", "Holy", "Discipline", "Arcane"]'::jsonb, 0),
  ('Classes', 2, 'Which Rogue talent tree focuses on stealth and openers?', '["Subtlety", "Assassination", "Combat", "Shadow"]'::jsonb, 0),
  ('Classes', 2, 'In Classic, which stance must a Warrior be in to use Shield Wall?', '["Defensive Stance", "Battle Stance", "Berserker Stance", "Any stance"]'::jsonb, 0),
  ('Classes', 2, 'Which Mage school does Frostbolt belong to?', '["Frost", "Arcane", "Fire", "Water"]'::jsonb, 0),
  ('Classes', 2, 'Which Druid ability restores mana to a target?', '["Innervate", "Rejuvenation", "Barkskin", "Tranquility"]'::jsonb, 0),
  ('Classes', 2, 'Which Paladin spell fully heals a target but drains the Paladin''s mana?', '["Lay on Hands", "Holy Light", "Divine Favor", "Flash of Light"]'::jsonb, 0),
  ('Classes', 3, 'How many talent points does a level 60 character have in Classic?', '["51", "50", "60", "41"]'::jsonb, 0),
  ('Classes', 2, 'At what level do characters earn their first talent point?', '["10", "1", "5", "20"]'::jsonb, 0),
  ('Classes', 2, 'Which Hunter shot is used to remove an enemy''s Enrage-style frenzy?', '["Tranquilizing Shot", "Concussive Shot", "Arcane Shot", "Scatter Shot"]'::jsonb, 0),
  ('Classes', 2, 'Which Warlock spell summons a party member to the Warlock''s location?', '["Ritual of Summoning", "Soul Link", "Demonic Gateway", "Eye of Kilrogg"]'::jsonb, 0),
  ('Classes', 1, 'Which class can Banish demons and elementals?', '["Warlock", "Mage", "Priest", "Paladin"]'::jsonb, 0),
  ('Classes', 2, 'Which Shaman totem removes poison from nearby allies over time?', '["Poison Cleansing Totem", "Tremor Totem", "Grounding Totem", "Healing Stream Totem"]'::jsonb, 0),
  ('Races', 1, 'Which race has the War Stomp racial ability?', '["Tauren", "Orc", "Troll", "Dwarf"]'::jsonb, 0),
  ('Races', 1, 'Which race has Will of the Forsaken?', '["Undead", "Human", "Orc", "Night Elf"]'::jsonb, 0),
  ('Races', 1, 'Which race has Shadowmeld?', '["Night Elf", "Undead", "Gnome", "Troll"]'::jsonb, 0),
  ('Races', 1, 'Which race has the Stoneform ability?', '["Dwarf", "Gnome", "Tauren", "Human"]'::jsonb, 0),
  ('Races', 2, 'Which race has the Escape Artist ability?', '["Gnome", "Night Elf", "Human", "Troll"]'::jsonb, 0),
  ('Races', 2, 'Which race has Berserking?', '["Troll", "Orc", "Tauren", "Undead"]'::jsonb, 0),
  ('Races', 2, 'Which race has Blood Fury?', '["Orc", "Troll", "Tauren", "Human"]'::jsonb, 0),
  ('Races', 2, 'In Classic, which Alliance races can be Paladins?', '["Human and Dwarf", "Human and Night Elf", "Dwarf and Gnome", "All Alliance races"]'::jsonb, 0),
  ('Races', 2, 'In Classic, Shamans are only available to which faction?', '["Horde", "Alliance", "Both factions", "Neutral"]'::jsonb, 0),
  ('Races', 1, 'Tauren begin their journey in which zone?', '["Mulgore", "Durotar", "The Barrens", "Tirisfal Glades"]'::jsonb, 0),
  ('Races', 1, 'Orcs and Trolls start in which zone?', '["Durotar", "Mulgore", "The Barrens", "Ashenvale"]'::jsonb, 0),
  ('Races', 1, 'Undead characters start in which zone?', '["Tirisfal Glades", "Silverpine Forest", "Duskwood", "Eastern Plaguelands"]'::jsonb, 0),
  ('Races', 1, 'Night Elves begin on which island?', '["Teldrassil", "Darkshore", "Azuremyst Isle", "Moonglade"]'::jsonb, 0),
  ('Races', 1, 'Dwarves and Gnomes start in which zone?', '["Dun Morogh", "Loch Modan", "Elwynn Forest", "Wetlands"]'::jsonb, 0),
  ('Lore', 1, 'Who is Warchief of the Horde in Classic?', '["Thrall", "Garrosh Hellscream", "Grom Hellscream", "Vol''jin"]'::jsonb, 0),
  ('Lore', 1, 'What is the capital city of the Forsaken?', '["Undercity", "Silvermoon", "Stratholme", "Lordaeron Keep"]'::jsonb, 0),
  ('Lore', 1, 'Who is the Banshee Queen of the Forsaken?', '["Sylvanas Windrunner", "Jaina Proudmoore", "Alleria Windrunner", "Lady Deathwhisper"]'::jsonb, 0),
  ('Lore', 1, 'What is the Tauren capital?', '["Thunder Bluff", "Camp Mojache", "Bloodhoof Village", "Orgrimmar"]'::jsonb, 0),
  ('Lore', 1, 'Who leads the Tauren in Classic?', '["Cairne Bloodhoof", "Baine Bloodhoof", "Hamuul Runetotem", "Magatha Grimtotem"]'::jsonb, 0),
  ('Lore', 2, 'Which troll tribe is allied with the Horde?', '["Darkspear", "Gurubashi", "Amani", "Sandfury"]'::jsonb, 0),
  ('Lore', 1, 'Who is the leader of the black dragonflight?', '["Deathwing", "Malygos", "Nozdormu", "Ysera"]'::jsonb, 0),
  ('Lore', 2, 'Onyxia hides in Stormwind under which disguise?', '["Lady Katrana Prestor", "Lady Sylvanas", "Lady Jaina", "Lady Prestwick"]'::jsonb, 0),
  ('Lore', 1, 'Ragnaros is the lord of which element?', '["Fire", "Earth", "Water", "Air"]'::jsonb, 0),
  ('Lore', 2, 'Which dwarf clan is enslaved by Ragnaros in Blackrock Mountain?', '["Dark Iron", "Bronzebeard", "Wildhammer", "Frostborn"]'::jsonb, 0),
  ('Lore', 1, 'Which prince of Lordaeron became the Lich King?', '["Arthas Menethil", "Anduin Lothar", "Varian Wrynn", "Uther Lightbringer"]'::jsonb, 0),
  ('Lore', 1, 'What is the Night Elf capital in Classic?', '["Darnassus", "Auberdine", "Astranaar", "Nighthaven"]'::jsonb, 0),
  ('Lore', 1, 'What is the Dwarven capital?', '["Ironforge", "Thelsamar", "Grim Batol", "Aerie Peak"]'::jsonb, 0),
  ('Lore', 2, 'Which King of Stormwind is missing when Classic begins?', '["Varian Wrynn", "Llane Wrynn", "Anduin Wrynn", "Terenas Menethil"]'::jsonb, 0),
  ('Lore', 2, 'Who leads the Burning Legion?', '["Sargeras", "Kil''jaeden", "Archimonde", "Mannoroth"]'::jsonb, 0),
  ('Lore', 2, 'Hakkar the Soulflayer is worshipped in which raid?', '["Zul''Gurub", "Zul''Farrak", "Zul''Aman", "Ahn''Qiraj"]'::jsonb, 0),
  ('Lore', 2, 'Which Old God awaits at the bottom of the Temple of Ahn''Qiraj?', '["C''Thun", "Yogg-Saron", "N''Zoth", "Y''Shaarj"]'::jsonb, 0),
  ('Lore', 1, 'Who rules Ironforge in Classic?', '["Magni Bronzebeard", "Muradin Bronzebeard", "Moira Thaurissan", "Falstad Wildhammer"]'::jsonb, 0),
  ('Lore', 2, 'Kel''Thuzad awaits the raid in which necropolis?', '["Naxxramas", "Acherus", "Scholomance", "Icecrown Citadel"]'::jsonb, 0),
  ('Lore', 2, 'Nefarian and Onyxia are the children of which dragon?', '["Deathwing", "Alexstrasza", "Malygos", "Sintharia"]'::jsonb, 0),
  ('Lore', 2, 'Ysera is the Aspect of which dragonflight?', '["Green", "Red", "Blue", "Bronze"]'::jsonb, 0),
  ('Lore', 2, 'Malygos is the Aspect of which dragonflight?', '["Blue", "Green", "Black", "Bronze"]'::jsonb, 0),
  ('Lore', 2, 'Alexstrasza is the Aspect of which dragonflight?', '["Red", "Green", "Blue", "Bronze"]'::jsonb, 0),
  ('Lore', 2, 'Who is the Aspect of the bronze dragonflight?', '["Nozdormu", "Chromie", "Anachronos", "Soridormi"]'::jsonb, 0),
  ('Lore', 2, 'Who originally wielded the Ashbringer?', '["Alexandros Mograine", "Tirion Fordring", "Uther Lightbringer", "Darion Mograine"]'::jsonb, 0),
  ('Lore', 2, 'Vaelastrasz, encountered in Blackwing Lair, is a dragon of which color?', '["Red", "Black", "Bronze", "Green"]'::jsonb, 0),
  ('Lore', 1, 'What city stands in ruins above the Undercity?', '["Lordaeron", "Stratholme", "Dalaran", "Gilneas"]'::jsonb, 0),
  ('Lore', 1, 'Which brotherhood of thieves plagues Westfall?', '["The Defias Brotherhood", "The Syndicate", "The Venture Co.", "The Bloodsail Buccaneers"]'::jsonb, 0),
  ('Lore', 2, 'Who leads the Defias Brotherhood in the Deadmines?', '["Edwin VanCleef", "Captain Greenskin", "Cookie", "Mr. Smite"]'::jsonb, 0),
  ('Professions', 1, 'Which gathering profession is usually paired with Blacksmithing?', '["Mining", "Herbalism", "Skinning", "Fishing"]'::jsonb, 0),
  ('Professions', 1, 'Skinning mainly supplies which crafting profession?', '["Leatherworking", "Tailoring", "Blacksmithing", "Engineering"]'::jsonb, 0),
  ('Professions', 1, 'Which profession brews potions and elixirs?', '["Alchemy", "Herbalism", "Cooking", "Enchanting"]'::jsonb, 0),
  ('Professions', 1, 'Which profession can disenchant items into magical materials?', '["Enchanting", "Alchemy", "Tailoring", "Jewelcrafting"]'::jsonb, 0),
  ('Professions', 1, 'Which profession sews bags out of cloth?', '["Tailoring", "Leatherworking", "Engineering", "First Aid"]'::jsonb, 0),
  ('Professions', 2, 'What are the two Engineering specializations in Classic?', '["Gnomish and Goblin", "Gnomish and Dwarven", "Goblin and Troll", "Arcane and Steam"]'::jsonb, 0),
  ('Professions', 2, 'What is the maximum profession skill level in Classic?', '["300", "225", "375", "450"]'::jsonb, 0),
  ('Professions', 2, 'Which herb is required for every Classic flask?', '["Black Lotus", "Peacebloom", "Silverleaf", "Mageroyal"]'::jsonb, 0),
  ('Professions', 2, 'Which profession transmutes Arcanite Bars?', '["Alchemy", "Blacksmithing", "Mining", "Enchanting"]'::jsonb, 0),
  ('Professions', 1, 'What is the highest-tier common cloth in Classic?', '["Runecloth", "Mageweave", "Silk", "Felcloth"]'::jsonb, 0),
  ('Professions', 2, 'Which cloth makes the Heavy Runecloth Bandage?', '["Runecloth", "Mageweave", "Silk Cloth", "Mooncloth"]'::jsonb, 0),
  ('Professions', 2, 'Which profession crafts Thorium Grenades?', '["Engineering", "Blacksmithing", "Alchemy", "Mining"]'::jsonb, 0),
  ('Professions', 2, 'Which profession crafts the Sulfuron Hammer, used to create Sulfuras?', '["Blacksmithing", "Engineering", "Enchanting", "Mining"]'::jsonb, 0),
  ('Professions', 1, 'Which profession lets you bandage yourself and others?', '["First Aid", "Alchemy", "Tailoring", "Cooking"]'::jsonb, 0),
  ('Professions', 2, 'Mooncloth is made by which profession?', '["Tailoring", "Enchanting", "Alchemy", "Leatherworking"]'::jsonb, 0),
  ('Professions', 2, 'Which ore do miners need for Arcanite Bars (along with an Arcane Crystal)?', '["Thorium", "Mithril", "Truesilver", "Dark Iron"]'::jsonb, 0),
  ('Professions', 2, 'Where do miners smelt Dark Iron ore?', '["Black Forge in Blackrock Depths", "The Great Forge in Ironforge", "Any forge", "Thorium Point"]'::jsonb, 0),
  ('World', 1, 'Molten Core is found inside which mountain?', '["Blackrock Mountain", "Mount Hyjal", "Grim Batol", "Thunder Bluff"]'::jsonb, 0),
  ('World', 1, 'Which raid holds Nefarian?', '["Blackwing Lair", "Molten Core", "Onyxia''s Lair", "Naxxramas"]'::jsonb, 0),
  ('World', 1, 'Onyxia''s Lair is in which zone?', '["Dustwallow Marsh", "Burning Steppes", "Swamp of Sorrows", "Feralas"]'::jsonb, 0),
  ('World', 1, 'The gates of Ahn''Qiraj are in which zone?', '["Silithus", "Tanaris", "Un''Goro Crater", "Feralas"]'::jsonb, 0),
  ('World', 1, 'Zul''Gurub is located in which zone?', '["Stranglethorn Vale", "The Hinterlands", "Tanaris", "Swamp of Sorrows"]'::jsonb, 0),
  ('World', 2, 'In Classic, Naxxramas floats above which zone?', '["Eastern Plaguelands", "Western Plaguelands", "Tirisfal Glades", "Icecrown"]'::jsonb, 0),
  ('World', 1, 'Who is the final boss of Molten Core?', '["Ragnaros", "Majordomo Executus", "Golemagg", "Sulfuron Harbinger"]'::jsonb, 0),
  ('World', 2, 'Which boss must be defeated to summon Ragnaros?', '["Majordomo Executus", "Golemagg the Incinerator", "Baron Geddon", "Garr"]'::jsonb, 0),
  ('World', 1, 'The Scarlet Monastery is in which zone?', '["Tirisfal Glades", "Western Plaguelands", "Silverpine Forest", "Alterac Mountains"]'::jsonb, 0),
  ('World', 1, 'Wailing Caverns is in which zone?', '["The Barrens", "Durotar", "Desolace", "Ashenvale"]'::jsonb, 0),
  ('World', 1, 'Ragefire Chasm lies beneath which city?', '["Orgrimmar", "Thunder Bluff", "Undercity", "Ironforge"]'::jsonb, 0),
  ('World', 1, 'Stratholme is in which zone?', '["Eastern Plaguelands", "Western Plaguelands", "Tirisfal Glades", "Alterac Mountains"]'::jsonb, 0),
  ('World', 2, 'Scholomance is in which zone?', '["Western Plaguelands", "Eastern Plaguelands", "Tirisfal Glades", "Silverpine Forest"]'::jsonb, 0),
  ('World', 2, 'Maraudon is in which zone?', '["Desolace", "Feralas", "Stonetalon Mountains", "Thousand Needles"]'::jsonb, 0),
  ('World', 2, 'Dire Maul is in which zone?', '["Feralas", "Desolace", "Azshara", "Felwood"]'::jsonb, 0),
  ('World', 2, 'Zul''Farrak is in which zone?', '["Tanaris", "Stranglethorn Vale", "Silithus", "Thousand Needles"]'::jsonb, 0),
  ('World', 1, 'The goblin port of Booty Bay is in which zone?', '["Stranglethorn Vale", "Tanaris", "The Barrens", "Swamp of Sorrows"]'::jsonb, 0),
  ('World', 1, 'The goblin town of Gadgetzan is in which zone?', '["Tanaris", "The Barrens", "Stranglethorn Vale", "Azshara"]'::jsonb, 0),
  ('World', 1, 'The Crossroads is in which zone?', '["The Barrens", "Durotar", "Mulgore", "Ashenvale"]'::jsonb, 0),
  ('World', 1, 'Hogger terrorizes which zone?', '["Elwynn Forest", "Westfall", "Redridge Mountains", "Duskwood"]'::jsonb, 0),
  ('World', 1, 'In which zone does the famous hunt for Mankrik''s wife take place?', '["The Barrens", "Desolace", "Stonetalon Mountains", "Thousand Needles"]'::jsonb, 0),
  ('World', 2, 'The famous Leeroy Jenkins wipe happened in which dungeon?', '["Upper Blackrock Spire", "Blackrock Depths", "Lower Blackrock Spire", "Molten Core"]'::jsonb, 0),
  ('World', 1, 'What carries travelers between Stormwind and Ironforge underground?', '["The Deeprun Tram", "A zeppelin", "A gryphon", "A mage portal"]'::jsonb, 0),
  ('World', 1, 'How do Horde players travel between Orgrimmar and Undercity?', '["Zeppelin", "Boat", "Tram", "Bat"]'::jsonb, 0),
  ('World', 2, 'Which zone is home to the Darkmoon Faire''s Horde-side location?', '["Mulgore", "Durotar", "The Barrens", "Tirisfal Glades"]'::jsonb, 0),
  ('Items', 2, 'What is Thunderfury''s full name?', '["Thunderfury, Blessed Blade of the Windseeker", "Thunderfury, Storm of the Windlord", "Thunderfury, Edge of the Tempest", "Thunderfury, Fang of Al''Akir"]'::jsonb, 0),
  ('Items', 3, 'Which two Molten Core bosses drop the Bindings of the Windseeker?', '["Garr and Baron Geddon", "Lucifron and Magmadar", "Gehennas and Shazzrah", "Golemagg and Sulfuron"]'::jsonb, 0),
  ('Items', 2, 'Which boss in Stratholme can drop the Deathcharger''s Reins mount?', '["Baron Rivendare", "Balnazzar", "Ramstein the Gorger", "Magistrate Barthilas"]'::jsonb, 0),
  ('Items', 2, 'Atiesh, Greatstaff of the Guardian is assembled from splinters found in which raid?', '["Naxxramas", "Molten Core", "Blackwing Lair", "Ahn''Qiraj"]'::jsonb, 0),
  ('Items', 1, 'What does a Hearthstone do?', '["Returns you to your bound inn", "Summons a mount", "Restores your mana", "Revives you"]'::jsonb, 0),
  ('Items', 3, 'Sulfuras, Hand of Ragnaros requires the Eye of Sulfuras, dropped by whom?', '["Ragnaros", "Majordomo Executus", "Sulfuron Harbinger", "Golemagg"]'::jsonb, 0),
  ('Items', 2, 'What does Onyxia''s head turn in for, besides a reward?', '["A buff for the whole city (Rallying Cry of the Dragonslayer)", "A new mount", "A guild tabard", "A free epic weapon"]'::jsonb, 0),
  ('Systems', 1, 'What is the maximum character level in Classic?', '["60", "70", "50", "80"]'::jsonb, 0),
  ('Systems', 1, 'At what level could players learn their first riding skill in Classic?', '["40", "30", "20", "60"]'::jsonb, 0),
  ('Systems', 1, 'How do you build up Rested experience?', '["Log out in an inn or city", "Kill elite monsters", "Complete dungeons", "Stand next to a campfire"]'::jsonb, 0),
  ('Systems', 1, 'In Warsong Gulch, how do you score?', '["Capture the enemy flag", "Hold resource nodes", "Kill the enemy general", "Escort a cart"]'::jsonb, 0),
  ('Systems', 2, 'How many capturable bases are there in Arathi Basin?', '["5", "3", "4", "6"]'::jsonb, 0),
  ('Systems', 2, 'Alterac Valley lies in which region?', '["Alterac Mountains", "Hillsbrad Foothills", "Arathi Highlands", "Silverpine Forest"]'::jsonb, 0),
  ('Systems', 2, 'What is the name of the traveling carnival that visits Azeroth?', '["The Darkmoon Faire", "The Midsummer Faire", "The Brewfest Fair", "The Lunar Carnival"]'::jsonb, 0),
  ('Systems', 2, 'Who runs the Darkmoon Faire?', '["Silas Darkmoon", "Sayge", "Flik", "Burth"]'::jsonb, 0),
  ('Systems', 1, 'What is the most common raid size for Molten Core in Classic?', '["40 players", "25 players", "20 players", "10 players"]'::jsonb, 0),
  ('Systems', 2, 'Zul''Gurub and Ruins of Ahn''Qiraj are raids for how many players?', '["20", "10", "25", "40"]'::jsonb, 0),
  ('Systems', 1, 'Which item quality color represents Epic items?', '["Purple", "Blue", "Orange", "Green"]'::jsonb, 0),
  ('Systems', 1, 'Which item quality color represents Legendary items?', '["Orange", "Purple", "Gold", "Red"]'::jsonb, 0),
  ('Systems', 1, 'Which item quality color represents Rare items?', '["Blue", "Green", "Purple", "White"]'::jsonb, 0),
  ('Systems', 2, 'What do Horde and Alliance players earn from Honorable Kills to climb the PvP ranks?', '["Honor", "Conquest", "Valor", "Marks of Justice"]'::jsonb, 0),
  ('Systems', 2, 'What is the highest PvP rank title for Horde in Classic?', '["High Warlord", "Grand Marshal", "Warlord", "General"]'::jsonb, 0),
  ('Systems', 2, 'What is the highest PvP rank title for Alliance in Classic?', '["Grand Marshal", "High Warlord", "Field Marshal", "Marshal"]'::jsonb, 0),
  ('Quotes', 1, 'Which boss shouts "BY FIRE BE PURGED!"?', '["Ragnaros", "Nefarian", "Baron Geddon", "Kel''Thuzad"]'::jsonb, 0),
  ('Quotes', 1, '"Many whelps! Handle it!" is a famous raid callout from which encounter?', '["Onyxia", "Nefarian", "Vaelastrasz", "Razorgore"]'::jsonb, 0),
  ('Quotes', 2, 'Which boss greets the raid with "Too soon! You have awakened me too soon, Executus!"?', '["Ragnaros", "Nefarian", "Onyxia", "Garr"]'::jsonb, 0),
  ('Quotes', 1, 'Murlocs famously make which sound?', '["Mrglglglgl!", "Lok''tar!", "Zug zug!", "Moo!"]'::jsonb, 0),
  ('Quotes', 1, 'What do Orc peons famously say when given a job?', '["Zug zug", "Mrglgl", "Lok''tar", "For the Horde"]'::jsonb, 0)
ON CONFLICT (question) DO NOTHING;

ALTER TABLE public.pending_games ADD COLUMN IF NOT EXISTS secret JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.pending_games DROP CONSTRAINT IF EXISTS pending_games_event_type_check;
ALTER TABLE public.pending_games ADD CONSTRAINT pending_games_event_type_check
  CHECK (event_type = ANY (ARRAY['fishing', 'blacksmith', 'murloc', 'trivia']));
ALTER TABLE public.game_events DROP CONSTRAINT IF EXISTS game_events_game_type_check;
ALTER TABLE public.game_events ADD CONSTRAINT game_events_game_type_check
  CHECK (game_type = ANY (ARRAY['fishing', 'blacksmith', 'murloc', 'trivia', 'normal_claim']));

CREATE OR REPLACE FUNCTION public.claim_sparkle_gold()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_status TEXT;
  v_last TIMESTAMP;
  v_claim_count INT;
  v_event_type TEXT;
  v_rand FLOAT;
  v_params JSONB;
  v_pending_id UUID;
  v_challenge TEXT;
  v_secret JSONB := '{}'::jsonb;
  v_q RECORD;
  v_order INT[];
  v_gold INT := 0;
  v_earned RECORD;
  v_capped BOOLEAN := false;
  v_mult NUMERIC;
  v_intervals FLOAT[];
  v_stddev FLOAT;
  c_cooldown CONSTANT INTERVAL := INTERVAL '20 seconds';
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Housekeeping for this player (keeps the tables small without a cron job)
  DELETE FROM pending_games WHERE user_id = v_user_id AND created_at < NOW() - INTERVAL '2 days';
  DELETE FROM sparkle_claims WHERE user_id = v_user_id AND created_at < NOW() - INTERVAL '2 days';

  SELECT MAX(created_at) INTO v_last FROM sparkle_claims WHERE user_id = v_user_id;
  IF v_last IS NOT NULL AND v_last > NOW() - c_cooldown THEN
    -- Sparkles spawn every 30-50 s, so a real player can't get here; a script can
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CLAIM_TOO_SOON', ARRAY['TOO_SOON'], 'LOW',
            jsonb_build_object('seconds_since_last', EXTRACT(EPOCH FROM (NOW() - v_last))));
    PERFORM add_cheat_points(v_user_id, 2);
    RETURN jsonb_build_object('success', false, 'error', 'too_soon');
  END IF;

  SELECT COUNT(*) INTO v_claim_count FROM sparkle_claims
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_claim_count >= 150 THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'CLAIM_SPAM', ARRAY['SPAM'], 'MEDIUM', jsonb_build_object('claims_per_hour', v_claim_count));
    PERFORM add_cheat_points(v_user_id, 10);
    RETURN jsonb_build_object('success', false, 'error', 'rate_limited');
  END IF;

  -- Robotic rhythm: the last 10 claims spaced almost exactly evenly
  SELECT array_agg(gap) INTO v_intervals FROM (
    SELECT EXTRACT(EPOCH FROM (created_at - LAG(created_at) OVER (ORDER BY created_at)))::FLOAT AS gap
    FROM (SELECT created_at FROM sparkle_claims WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 11) last11
  ) g WHERE gap IS NOT NULL AND gap < 300;
  IF array_length(v_intervals, 1) >= 10 THEN
    SELECT stddev_pop(x) INTO v_stddev FROM unnest(v_intervals) x;
    IF v_stddev < 0.4 THEN
      INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
      VALUES (v_user_id, 'ROBOTIC_RHYTHM', ARRAY['ROBOTIC_INTERVALS'], 'MEDIUM', jsonb_build_object('stddev_s', v_stddev));
      PERFORM add_cheat_points(v_user_id, 20);
    END IF;
  END IF;

  INSERT INTO sparkle_claims (user_id) VALUES (v_user_id);
  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;

  v_rand := random();
  v_event_type := CASE WHEN v_rand < 0.20 THEN 'fishing' WHEN v_rand < 0.40 THEN 'blacksmith'
                       WHEN v_rand < 0.60 THEN 'murloc' WHEN v_rand < 0.75 THEN 'trivia' ELSE NULL END;

  IF v_event_type IS NULL THEN
    -- Plain sparkle: small gold, unless banned or capped
    SELECT * INTO v_earned FROM minigame_earned_today(v_user_id);
    v_mult := minigame_gold_multiplier(v_earned.gold);
    IF v_status IN ('SOFT_BAN', 'BANNED') THEN
      v_gold := 0;
    ELSE
      v_gold := round((8 + (random() * 7)::INT) * v_mult)::INT;
      v_capped := v_mult < 1;
      UPDATE profiles SET gold = COALESCE(gold, 0) + v_gold,
                          gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold
      WHERE id = v_user_id;
    END IF;
    INSERT INTO game_events (user_id, game_type, won, gold_awarded, flags, severity)
    VALUES (v_user_id, 'normal_claim', TRUE, v_gold, ARRAY[]::TEXT[], 'LOW');
    RETURN jsonb_build_object('success', true, 'event', NULL, 'awarded', v_gold, 'capped', v_capped,
                              'weary', minigame_weary_state(v_user_id),
                              'total', (SELECT gold FROM profiles WHERE id = v_user_id));
  END IF;

  v_params := CASE v_event_type
    WHEN 'fishing' THEN jsonb_build_object(
      'zone_start', -80 + floor(random() * 134)::INT, 'zone_width', 26, 'sweep_ms', 1400, 'game_ms', 6000, 'idle_ms', 6000)
    WHEN 'murloc' THEN jsonb_build_object(
      'count', 3 + floor(random() * 3)::INT, 'duration_ms', 4500)
    WHEN 'blacksmith' THEN jsonb_build_object(
      'cycle_ms', 1400, 'hit_window', 0.15, 'hits_needed', 3, 'max_attempts', 5, 'game_ms', 10000)
    ELSE '{}'::jsonb
  END;

  IF v_event_type = 'trivia' THEN
    -- A question this player hasn't seen in their last 40 trivia games, answers shuffled every time.
    -- The browser gets the question and options only; the correct option stays in pending_games.secret.
    SELECT tq.* INTO v_q FROM trivia_questions tq
    WHERE tq.active AND tq.id NOT IN (
      SELECT (pg.secret->>'qid')::INT FROM pending_games pg
      WHERE pg.user_id = v_user_id AND pg.event_type = 'trivia' AND pg.secret ? 'qid'
      ORDER BY pg.created_at DESC LIMIT 40)
    ORDER BY random() LIMIT 1;
    IF v_q.id IS NULL THEN SELECT tq.* INTO v_q FROM trivia_questions tq WHERE tq.active ORDER BY random() LIMIT 1; END IF;
    SELECT array_agg(i ORDER BY random()) INTO v_order FROM generate_series(0, 3) i;
    v_params := jsonb_build_object(
      'question', v_q.question, 'category', v_q.category, 'time_ms', 15000,
      'answers', jsonb_build_array(v_q.answers->v_order[1], v_q.answers->v_order[2], v_q.answers->v_order[3], v_q.answers->v_order[4]));
    v_secret := jsonb_build_object('qid', v_q.id, 'correct', array_position(v_order, v_q.correct_index) - 1);
  END IF;

  v_challenge := gen_random_challenge(32);
  INSERT INTO pending_games (user_id, event_type, challenge, challenge_expires, created_at_epoch, params, secret)
  VALUES (v_user_id, v_event_type, v_challenge, NOW() + INTERVAL '30 seconds',
          (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT, v_params, v_secret)
  RETURNING id INTO v_pending_id;

  RETURN jsonb_build_object('success', true, 'pending_id', v_pending_id, 'challenge', v_challenge,
                            'event', v_event_type, 'params', v_params, 'nonce', gen_random_uuid(), 'awarded', 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_sparkle_event(
  p_pending_id uuid, p_won boolean, p_challenge text, p_signature text, p_nonce uuid,
  p_client_time_ms bigint, p_client_timings jsonb, p_payload text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_rec RECORD;
  v_p JSONB;
  v_t INT[];
  v_n INT;
  v_won BOOLEAN := false;
  v_reaction INT;
  v_flags TEXT[] := ARRAY[]::TEXT[];
  v_points INT := 0;
  v_server_elapsed BIGINT;
  v_status TEXT;
  v_earned RECORD;
  v_gold INT := 0;
  v_food INT := 0;
  v_capped BOOLEAN := false;
  v_mult NUMERIC;
  -- fishing
  v_pos FLOAT; v_angle FLOAT; v_zone_start FLOAT; v_zone_end FLOAT;
  -- blacksmith
  v_hits INT := 0; v_attempts INT := 0; v_last_cycle INT := -1; v_cycle INT; v_phase FLOAT; i INT;
  c_food_cap CONSTANT INT := 60;
  c_min_reaction CONSTANT INT := 120; -- ms; faster than any human reaction
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  SELECT * INTO v_rec FROM pending_games WHERE id = p_pending_id FOR UPDATE; -- includes secret
  IF v_rec.id IS NULL OR v_rec.user_id <> v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_found');
  END IF;
  IF v_rec.won IS NOT NULL THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'REPLAY_ATTEMPT', ARRAY['REPLAY'], 'HIGH', jsonb_build_object('pending_id', p_pending_id));
    PERFORM add_cheat_points(v_user_id, 30);
    RETURN jsonb_build_object('success', false, 'error', 'already_resolved');
  END IF;

  -- Integrity: the stored challenge must sign the payload (a hand-edited request fails here)
  IF p_challenge IS DISTINCT FROM v_rec.challenge
     OR encode(extensions.hmac(p_payload, v_rec.challenge, 'sha256'), 'hex') IS DISTINCT FROM p_signature THEN
    v_flags := array_append(v_flags, 'SIGNATURE_MISMATCH'); v_points := v_points + 40;
  END IF;

  v_server_elapsed := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT - v_rec.created_at_epoch;
  IF v_rec.challenge_expires < NOW() THEN
    v_flags := array_append(v_flags, 'EXPIRED');
  END IF;

  -- Click timings as integers
  SELECT COALESCE(array_agg(round(x::numeric)::INT ORDER BY ord), ARRAY[]::INT[]) INTO v_t
  FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_client_timings) = 'array' THEN p_client_timings ELSE '[]'::jsonb END)
       WITH ORDINALITY AS e(x, ord)
  WHERE x ~ '^-?[0-9]+(\.[0-9]+)?$';
  v_n := COALESCE(array_length(v_t, 1), 0);
  v_p := v_rec.params;

  IF v_rec.event_type = 'fishing' AND v_n >= 2 THEN
    v_reaction := v_t[2]; -- gauge click after the gauge appears
    v_zone_start := (v_p->>'zone_start')::FLOAT;
    v_zone_end := v_zone_start + (v_p->>'zone_width')::FLOAT;
    v_pos := (v_t[2] % (v_p->>'sweep_ms')::INT)::FLOAT / (v_p->>'sweep_ms')::FLOAT;
    v_angle := CASE WHEN v_pos < 0.5 THEN -90 + (v_pos / 0.5) * 180 ELSE 90 - ((v_pos - 0.5) / 0.5) * 180 END;
    v_won := v_t[2] <= (v_p->>'game_ms')::INT AND v_angle BETWEEN v_zone_start - 2 AND v_zone_end + 2;
    IF v_t[1] + v_t[2] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'murloc' AND v_n >= 1 THEN
    v_reaction := v_t[1];
    v_won := v_n = (v_p->>'count')::INT AND v_t[v_n] <= (v_p->>'duration_ms')::INT + 150;
    FOR i IN 2..v_n LOOP
      IF v_t[i] < v_t[i - 1] THEN v_won := false; END IF;
      IF v_t[i] - v_t[i - 1] < 60 THEN
        v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; EXIT;
      END IF;
    END LOOP;
    IF v_t[v_n] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'blacksmith' AND v_n >= 1 THEN
    v_reaction := v_t[1];
    FOR i IN 1..v_n LOOP
      EXIT WHEN v_attempts >= (v_p->>'max_attempts')::INT OR v_hits >= (v_p->>'hits_needed')::INT;
      IF v_t[i] > (v_p->>'game_ms')::INT THEN EXIT; END IF;
      v_cycle := v_t[i] / (v_p->>'cycle_ms')::INT;
      IF v_cycle = v_last_cycle THEN CONTINUE; END IF; -- one counted swing per hammer cycle
      v_last_cycle := v_cycle;
      v_phase := (v_t[i] % (v_p->>'cycle_ms')::INT)::FLOAT / (v_p->>'cycle_ms')::FLOAT;
      v_attempts := v_attempts + 1;
      IF v_phase < (v_p->>'hit_window')::FLOAT THEN v_hits := v_hits + 1; END IF;
    END LOOP;
    v_won := v_hits >= (v_p->>'hits_needed')::INT;
    IF v_t[v_n] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;

  ELSIF v_rec.event_type = 'trivia' AND v_n >= 2 THEN
    -- timings: [ms until the answer was clicked, chosen option 0-3]
    v_reaction := v_t[1];
    v_won := v_t[2] = (v_rec.secret->>'correct')::INT AND v_t[1] <= (v_p->>'time_ms')::INT + 500;
    IF v_t[1] < 900 THEN -- nobody reads a question and four answers in under a second
      v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; v_won := false;
    END IF;
    IF v_t[1] > v_server_elapsed + 3000 THEN
      v_flags := array_append(v_flags, 'TIME_MISMATCH'); v_points := v_points + 15; v_won := false;
    END IF;
  END IF;

  -- (blacksmith's first swing can legitimately land in the opening window, so it isn't checked)
  IF v_rec.event_type NOT IN ('blacksmith', 'trivia') AND v_reaction IS NOT NULL AND v_reaction < c_min_reaction THEN
    v_flags := array_append(v_flags, 'SUPERHUMAN_SPEED'); v_points := v_points + 15; v_won := false;
  END IF;
  -- The browser claims a win the clicks don't support: a tampered or scripted client
  IF p_won AND NOT v_won AND NOT ('SUPERHUMAN_SPEED' = ANY(v_flags)) THEN
    v_flags := array_append(v_flags, 'CLIENT_WIN_MISMATCH'); v_points := v_points + 10;
  END IF;
  IF 'EXPIRED' = ANY(v_flags) OR 'SIGNATURE_MISMATCH' = ANY(v_flags) THEN v_won := false; END IF;

  UPDATE pending_games SET won = v_won, resolved_at = NOW() WHERE id = p_pending_id;

  SELECT status INTO v_status FROM user_cheat_scores WHERE user_id = v_user_id;
  IF v_won AND COALESCE(v_status, 'CLEAN') NOT IN ('SOFT_BAN', 'BANNED') THEN
    SELECT * INTO v_earned FROM minigame_earned_today(v_user_id);
    v_gold := CASE v_rec.event_type
      WHEN 'fishing' THEN 25 + (random() * 10)::INT
      WHEN 'murloc' THEN 15 + (random() * 10)::INT
      WHEN 'trivia' THEN 20 + (random() * 15)::INT
      ELSE 20 + (random() * 10)::INT END;
    v_food := CASE WHEN v_rec.event_type IN ('murloc', 'fishing') THEN 2 + floor(random() * 3)::INT ELSE 0 END;
    -- Weary: payouts taper the more mini-game gold you've earned today
    v_mult := minigame_gold_multiplier(v_earned.gold);
    v_gold := round(v_gold * v_mult)::INT;
    v_capped := v_mult < 1;
    IF v_earned.food + v_food > c_food_cap THEN v_food := GREATEST(c_food_cap - v_earned.food, 0); v_capped := true; END IF;
    IF v_gold > 0 OR v_food > 0 THEN
      UPDATE profiles
      SET gold = COALESCE(gold, 0) + v_gold, gold_earned_total = COALESCE(gold_earned_total, 0) + v_gold,
          food = COALESCE(food, 0) + v_food, food_earned_total = COALESCE(food_earned_total, 0) + v_food
      WHERE id = v_user_id;
    END IF;
  END IF;

  INSERT INTO game_events (user_id, pending_id, game_type, won, gold_awarded, food_awarded, client_timings,
                           client_submit_time_ms, flags, severity, reaction_ms, client_claimed_win, cheat_score_delta)
  VALUES (v_user_id, p_pending_id, v_rec.event_type, v_won, v_gold, v_food, p_client_timings, p_client_time_ms,
          v_flags, CASE WHEN v_points >= 30 THEN 'HIGH' WHEN v_points > 0 THEN 'MEDIUM' ELSE 'LOW' END,
          v_reaction, p_won, v_points);

  IF v_points > 0 THEN
    INSERT INTO cheat_audit_log (user_id, event_type, flags, severity, details)
    VALUES (v_user_id, 'GAME_FLAGGED', v_flags, CASE WHEN v_points >= 30 THEN 'HIGH' ELSE 'MEDIUM' END,
            jsonb_build_object('pending_id', p_pending_id, 'game', v_rec.event_type, 'timings', p_client_timings,
                               'reaction_ms', v_reaction, 'server_elapsed_ms', v_server_elapsed));
    PERFORM add_cheat_points(v_user_id, v_points);
  END IF;

  RETURN jsonb_build_object(
    'success', v_won, 'won', v_won, 'capped', v_capped, 'weary', minigame_weary_state(v_user_id),
    'answer', CASE WHEN v_rec.event_type = 'trivia' THEN (v_rec.secret->>'correct')::INT END, -- revealed only after the game is decided
    'awarded', v_gold, 'food_awarded', v_food,
    'total', (SELECT gold FROM profiles WHERE id = v_user_id),
    'food_total', (SELECT food FROM profiles WHERE id = v_user_id));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_sparkle_gold() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_sparkle_gold() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolve_sparkle_event(uuid, boolean, text, text, uuid, bigint, jsonb, text) TO authenticated;
