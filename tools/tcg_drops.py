"""Hated TCG card drops: which cards a creature can drop, written out for both sides.

A kill can drop a card in game (the addon rolls it from the creature's spawn id) and the tcg-sync server rolls it
again when you sync, so both must use the same tables in the same order. Edit the tables HERE, then run
    python tools/tcg_drops.py
which writes addons/HatedCompanion/HatedTCGDropData.lua and supabase/functions/tcg-sync/drop_data.ts.
Bump VERSION whenever a table changes (it's part of every roll's seed).

Cards only drop from their own kind of creature:
  1. NAMED   a card named after that very creature (Hogger drops Hogger, Ragnaros drops Ragnaros) - better odds
  2. FAMILY  a card of the creature's kind, by a word in its name (kobolds drop Kobold cards, gnolls Gnoll cards,
             the Scarlet Crusade Scarlet cards...: FAMILIES below)
  3. TRIBE   a card of the creature's race: by name (murlocs, pirates, quilboar), else by creature type (beast,
             undead, dragonkin, demon, elemental, mechanical)
  Anything else drops no card.
A creature with a class (a word in its name: "Druid of the Fang" is a druid - WoW calls nearly every NPC a warrior,
paladin, rogue or mage, so the real class has to come from the name) has a 1 in HERO_ODDS chance per kill at one of
that class's hero cards; that's all a class gives.
Card data: the renderer's manifest (Documents/Hearthstone Art/manifest.json).
"""
import json, os, re, sys

VERSION = 3
HERO_ODDS = 100
HOLO_ODDS = 50            # a dropped Rare, Epic, Legendary or hero is holographic 1 in 50 (2%, like packs)
# 1 in N per kill, by kind of kill
ODDS = {'normal': 200, 'elite': 80, 'rare': 25, 'worldboss': 10, 'dungeonboss': 20, 'raidboss': 10, 'named': 20}
# % per rarity (common, uncommon, rare, epic, legendary): ordinary kills / rares, bosses and raids
RARITY_PCT = {'low': [50, 30, 14, 5, 1], 'high': [30, 32, 23, 11, 4]}
RARITIES = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary']

# creature name in game -> the cards named after it (card names exactly as in the manifest)
NAMED = {
    'Hogger': ['Hogger', 'Hogger, Doom of Elwynn', 'Chainbreaker Hogger'],
    'Edwin VanCleef': ['Edwin VanCleef', 'Edwin, Defias Kingpin'],
    'Captain Greenskin': ['Captain Greenskin'],
    'Cookie': ['Cookie the Cook'],
    'Mr. Smite': ['Mr. Smite'],
    'Lady Anacondra': ['Lady Anacondra'],
    'Mutanus the Devourer': ['Mutanus the Devourer'],
    'Kresh': ['Kresh, Lord of Turtling'],
    'Bloodmage Thalnos': ['Bloodmage Thalnos'],
    'Plaguemaw the Rotting': ['Plaguemaw the Rotting'],
    'Mordresh Fire Eye': ['Mordresh Fire Eye'],
    'Old Murk-Eye': ['Old Murk-Eye'],
    'King Mukla': ['King Mukla'],
    'Barak Kodobane': ['Barak Kodobane'],
    'The Beast': ['The Beast'],
    'Warchief Rend Blackhand': ['Rend Blackhand'],
    'Rend Blackhand': ['Rend Blackhand'],
    'Emperor Dagran Thaurissan': ['Emperor Thaurissan'],
    'Baron Rivendare': ['Baron Rivendare'],
    'Ragnaros': ['Ragnaros the Firelord'],
    'Majordomo Executus': ['Majordomo Executus'],
    'Baron Geddon': ['Baron Geddon'],
    'Onyxia': ['Onyxia', 'Raid Boss Onyxia'],
    'Nefarian': ['Nefarian'],
    'Chromaggus': ['Chromaggus'],
    'Hakkar': ['Hakkar, the Soulflayer'],
    'High Priest Thekal': ['High Priest Thekal'],
    "High Priestess Jeklik": ['High Priestess Jeklik'],
    'Princess Huhuran': ['Princess Huhuran'],
    'Maexxna': ['Maexxna'],
    'Loatheb': ['Loatheb'],
    'Feugen': ['Feugen'],
    'Stalagg': ['Stalagg'],
    "Kel'Thuzad": ["Kel'Thuzad", "Headmaster Kel'Thuzad"],
    'Emeriss': ['Emeriss'],
    'Ysondre': ['Ysondre'],
    # Alterac Valley
    "Drek'Thar": ["Drek'Thar"],
    'Vanndar Stormpike': ['Vanndar Stormpike'],
    'Captain Galvangar': ['Captain Galvangar'],
    'Captain Balinda Stonehearth': ['Balinda Stonehearth'],
    'Korrak the Bloodrager': ['Korrak the Bloodrager'],
    'Lokholar the Ice Lord': ['Lokholar the Ice Lord'],
    'Ivus the Forest Lord': ['Ivus, the Forest Lord'],
    'Wing Commander Ichman': ['Wing Commander Ichman'],
    'Wing Commander Mulverick': ['Wing Commander Mulverick'],
    # faction leaders and town folk the other side can fight
    'Thrall': ['Thrall'],
    'Cairne Bloodhoof': ['Cairne Bloodhoof'],
    'Lady Sylvanas Windrunner': ['Sylvanas Windrunner'],
    "Vol'jin": ["Shadow Hunter Vol'jin"],
    'Highlord Bolvar Fordragon': ['Highlord Fordragon'],
    'Lady Katrana Prestor': ['Lady Prestor'],
    'High Tinker Mekkatorque': ['Gelbin Mekkatorque'],
    'Mankrik': ['Mankrik'],
    'Apothecary Helbrim': ['Apothecary Helbrim'],
    'Guff Runetotem': ['Guff Runetotem'],
    'Neeru Fireblade': ['Neeru Fireblade'],
    'Nat Pagle': ['Nat Pagle'],
    'Tirion Fordring': ['Tirion Fordring'],
}
# tribe by a word in the creature's name (checked before class)
TRIBE_WORDS = {
    'MURLOC': ['murloc', 'mrgl'],
    'PIRATE': ['pirate', 'buccaneer', 'swashbuckler', 'bloodsail', 'southsea', 'corsair', 'deckhand', 'privateer'],
    'QUILBOAR': ['quilboar', 'razormane', 'bristleback', 'razorfen', "death's head"],
}
# class by a word in the creature's name
CLASS_WORDS = {
    'DRUID': ['druid', 'dreamweaver'],
    'SHAMAN': ['shaman', 'seer', 'mystic', 'oracle', 'totemic', 'stormer', 'windcaller', 'earthcaller', 'stormcaller', 'witch doctor'],
    'PRIEST': ['priest', 'priestess', 'cleric', 'acolyte', 'confessor', 'chaplain', 'abbot', 'monk'],
    'WARLOCK': ['warlock', 'shadowcaster', 'summoner', 'necromancer', 'dreadcaster', 'netherseer', 'cultist', 'felcaller'],
    'MAGE': ['mage', 'magus', 'conjurer', 'conjuror', 'sorcerer', 'sorceress', 'arcanist', 'evoker', 'pyromancer', 'geomancer', 'wizard', 'magister', 'enchanter'],
    'ROGUE': ['rogue', 'thief', 'assassin', 'cutthroat', 'pilferer', 'footpad', 'bandit', 'shadowstalker', 'cutpurse', 'highwayman', 'ambusher'],
    'HUNTER': ['hunter', 'trapper', 'tracker', 'marksman', 'ranger', 'beastmaster', 'huntsman', 'poacher', 'stalker'],
    'PALADIN': ['paladin', 'crusader', 'templar', 'knight', 'zealot', 'lightbringer'],
    'WARRIOR': ['warrior', 'brute', 'berserker', 'gladiator', 'soldier', 'enforcer', 'warlord', 'champion', 'myrmidon', 'mercenary', 'thug'],
}
# creature type letter (HatedTCGDailyData's CTYPE) -> card tribe
# creature families with no Hearthstone race: a word in the creature's name -> the cards of that kind
# (checked before the tribe words; the cards go in their own pool, by rarity, like a tribe's)
FAMILIES = {
    'KOBOLD':     (['kobold'], ['Kobold Geomancer', 'Kobold Taskmaster']),
    'GNOLL':      (['gnoll'], ['Goldshire Gnoll', 'Wildpaw Gnoll']),
    'OGRE':       (['ogre'], ['Ogre Magi', 'Boulderfist Ogre']),
    'HARPY':      (['harpy'], ['Windfury Harpy', 'Snowblind Harpy']),
    'DEFIAS':     (['defias'], ['Defias Ringleader']),
    'SCARLET':    (['scarlet'], ['Scarlet Crusader', 'Scarlet Purifier']),
    'DARKIRON':   (['dark iron'], ['Dark Iron Dwarf', 'Dark Iron Skulker']),
    'VENTURE':    (['venture'], ['Venture Co. Mercenary']),
    'TROLL':      (['troll', 'gurubashi', 'amani', 'darkspear', 'skullsplitter', 'bloodscalp', 'witherbark', 'vilebranch',
                    'smolderthorn', 'sandfury', 'frostmane', 'mossflayer', 'shadowpine', 'zandalar', 'hakkari'],
                   ['Gurubashi Berserker', 'Amani Berserker', 'Darkspear Berserker', 'Troll Centurion', 'Voodoo Doctor']),
    'TROGG':      (['trogg'], ['Irondeep Trogg']),
    'CENTAUR':    (['centaur', 'kolkar', 'galak', 'maraudine', 'gelkis', 'magram'], ['Kolkar Pack Runner']),
    'WORGEN':     (['worgen'], ['Raging Worgen', 'Worgen Infiltrator']),
    'LEPERGNOME': (['leper gnome'], ['Leper Gnome']),
    'OOZE':       (['ooze', 'slime', 'sludge'], ['Acidic Swamp Ooze', 'Echoing Ooze', 'Devouring Ectoplasm']),
    'YETI':       (['yeti'], ['Chillwind Yeti', 'Coldtooth Yeti']),
    'GOLEM':      (['golem'], ['Arcane Golem', 'War Golem']),
    'CULTIST':    (['cultist', 'burning blade', 'twilight'], ['Burning Blade Acolyte', 'Cult Master', 'Dark Cultist']),
    'FLAMEWAKER': (['flamewaker'], ['Flamewaker']),
    'BLACKWING':  (['blackwing'], ['Blackwing Technician', 'Blackwing Corruptor']),
    'QIRAJI':     (['anubisath', 'qiraji'], ['Anubisath Sentinel', 'Skeram Cultist']),
    'PRISONER':   (['prisoner', 'inmate', 'convict'], ['Stockades Prisoner']),
    'WISP':       (['wisp'], ['Wisp']),
    'STORMPIKE':  (['stormpike'], ['Stormpike Commando', 'Stormpike Marshal']),
    'FROSTWOLF':  (['frostwolf'], ['Frostwolf Grunt', 'Frostwolf Warlord']),
    'STORMWIND':  (['stormwind'], ['Stormwind Guard', 'Stormwind Knight']),
    'KORKRON':    (["kor'kron"], ["Kor'kron Elite"]),
    'WARSONG':    (['warsong'], ['Warsong Commander']),
    'BOOTYBAY':   (['booty bay'], ['Booty Bay Bodyguard']),
    'GRIMTOTEM':  (['grimtotem'], ['Grimtotem Bounty Hunter']),
    'SENJIN':     (["sen'jin"], ["Sen'jin Shieldmasta"]),
    'GIANT':      (['giant'], ['Mountain Giant', 'Sea Giant', 'Molten Giant']),
}
# cards that belong to a race but aren't tagged with it -> that race's pool too
EXTRA_RACE = {
    'ELEMENTAL': ['Fire Elemental', 'Earth Elemental', 'Water Elemental', 'Frost Elemental', 'Dust Devil', 'Fen Creeper', 'Unbound Elemental'],
    'UNDEAD': ['Abomination', 'Flesheating Ghoul', 'Grave Defiler'],
    'QUILBOAR': ['Razorfen Hunter'],
}
CTYPE_TRIBE = {'B': 'BEAST', 'U': 'UNDEAD', 'K': 'DRAGON', 'D': 'DEMON', 'E': 'ELEMENTAL', 'M': 'MECHANICAL'}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(os.path.expanduser('~'), 'Documents', 'Hearthstone Art', 'manifest.json')
norm = lambda s: re.sub(r'[^a-z]', '', s.lower())


def build():
    cards = json.load(open(sys.argv[1] if len(sys.argv) > 1 else MANIFEST, encoding='utf-8'))
    by_name = {}
    for c in cards: by_name.setdefault(c['name'], []).append(c)
    rix = lambda c: RARITIES.index(c['ourRarity'])
    named = {}
    for creature, names in NAMED.items():
        dbfs = []
        for n in names:
            if n not in by_name: sys.exit(f'NAMED: no card called {n!r}')
            dbfs += [c['dbfId'] for c in by_name[n]]
        named[norm(creature)] = sorted(set(dbfs))
    def pools(pred):
        out = [[] for _ in RARITIES]
        for c in cards:
            if c['type'] != 'HERO' and pred(c): out[rix(c)].append(c['dbfId'])
        return [sorted(p) for p in out]
    for name in [n for _, cs in FAMILIES.values() for n in cs] + [n for cs in EXTRA_RACE.values() for n in cs]:
        if name not in by_name: sys.exit(f'FAMILIES / EXTRA_RACE: no card called {name!r}')
    extra = {n: t for t, cs in EXTRA_RACE.items() for n in cs}
    tribes = {t: pools(lambda c, t=t: c['race'] == t or extra.get(c['name']) == t) for t in sorted(set(TRIBE_WORDS) | set(CTYPE_TRIBE.values()))}
    for f, (_, names) in FAMILIES.items():
        tribes[f] = pools(lambda c, names=names: c['name'] in names)
    heroes = {k: sorted(c['dbfId'] for c in cards if c['type'] == 'HERO' and c['cardClass'] == k) for k in CLASS_WORDS}
    rarity = {c['dbfId']: rix(c) + 1 for c in cards}
    for k, v in heroes.items():
        if not v: sys.exit(f'no hero card for {k}')
    return dict(version=VERSION, heroOdds=HERO_ODDS, holoOdds=HOLO_ODDS, rarity=rarity, odds=ODDS, rarityPct=RARITY_PCT, named=named,
                tribeWords={**{f: w for f, (w, _) in FAMILIES.items()}, **TRIBE_WORDS}, tribeOrder=list(FAMILIES) + list(TRIBE_WORDS), classWords=CLASS_WORDS, classOrder=list(CLASS_WORDS), ctypeTribe=CTYPE_TRIBE,
                tribes=tribes, heroes=heroes), rarity


def lua(v, ind=''):
    if isinstance(v, dict):
        items = []
        for k in sorted(v):
            key = f'[{k}]' if isinstance(k, int) else (k if re.match(r'^[A-Za-z_]\w*$', k) else '[' + json.dumps(k) + ']')
            items.append(f'{ind}  {key} = {lua(v[k], ind + "  ")}')
        return '{\n' + ',\n'.join(items) + f'\n{ind}}}'
    if isinstance(v, list): return '{ ' + ', '.join(lua(x, ind) for x in v) + ' }'
    if isinstance(v, str): return json.dumps(v)
    return str(v)


if __name__ == '__main__':
    data, rarity = build()
    open(os.path.join(ROOT, 'addons/HatedCompanion/HatedTCGDropData.lua'), 'w', encoding='utf-8', newline='\n').write(
        '-- Generated by tools/tcg_drops.py - do not edit by hand.\nHatedTCG_DROPS = ' + lua(data) + '\n')
    open(os.path.join(ROOT, 'supabase/functions/tcg-sync/drop_data.ts'), 'w', encoding='utf-8', newline='\n').write(
        '// Generated by tools/tcg_drops.py - do not edit by hand.\nexport const DROPS: any = ' + json.dumps(data, separators=(',', ':')) + ';\n')
    print(f"v{VERSION}: {len(data['named'])} named creatures, tribes {', '.join(f'{t}={sum(map(len, p))}' for t, p in data['tribes'].items())}")
