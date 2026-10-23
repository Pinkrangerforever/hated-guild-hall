"""Hated TCG daily challenges: the shared tables, written out for both sides.

The addon picks each character's daily board itself (no sync needed) and the tcg-sync server picks the same board
again to check it, so both must use the exact same tables in the exact same order. Edit them HERE, then run
    python tools/tcg_daily.py
which writes addons/HatedCompanion/HatedTCGDailyData.lua and supabase/functions/tcg-sync/daily_data.ts.
Changing a table changes boards: bump VERSION when you do (it's part of the board's seed).

Dungeons and level ranges: WoW Forever's list (Warcraft Tavern's dungeon guide, Blizzard's new-dungeons post).
Wings that share one instance (Scarlet Monastery, Blackrock Spire, Dire Maul, Stratholme) are one entry: the
game reports them as the same place, so the addon can't tell the wings apart.
"""
import json, os

VERSION = 1
DUNGEON_POINTS = 250
DUNGEON_TRASH = 5          # verified (spawn id) kills inside the dungeon's instance needed alongside the bosses

# key, name (as GetInstanceInfo says it), other names, min level, max level, faction ('' both, 'H', 'A'),
# instance map id (None: not known yet - matched by name), bosses to defeat for the clear
DUNGEONS = [
    ('rfc',    'Ragefire Chasm',            [],                          13, 18, 'H', 389, 3),
    ('hot',    'Hall of Thanes',            [],                          13, 18, 'A', None, 3),
    ('rol',    'Ruins of Lordaeron',        [],                          15, 20, '',  None, 3),
    ('dm',     'The Deadmines',             ['Deadmines'],               15, 22, '',  36,   3),
    ('wc',     'Wailing Caverns',           [],                          17, 24, '',  43,   3),
    ('sfk',    'Shadowfang Keep',           [],                          20, 26, '',  33,   3),
    ('bfd',    'Blackfathom Deeps',         [],                          22, 28, '',  48,   3),
    ('es',     'Excavation Site',           [],                          24, 29, '',  None, 3),
    ('stocks', 'The Stockade',              ['Stormwind Stockade'],      25, 29, 'A', 34,   3),
    ('cod',    'City of Dalaran',           ['Dalaran'],                 28, 33, '',  None, 3),
    ('gnomer', 'Gnomeregan',                [],                          29, 38, '',  90,   3),
    ('rfk',    'Razorfen Kraul',            [],                          29, 38, '',  47,   3),
    ('sm',     'Scarlet Monastery',         [],                          30, 46, '',  189,  2),
    ('dc',     'The Drowned City',          ['Drowned City'],            35, 40, '',  None, 3),
    ('uld',    'Uldaman',                   [],                          36, 45, '',  70,   3),
    ('rfd',    'Razorfen Downs',            [],                          37, 46, '',  129,  3),
    ('zf',     "Zul'Farrak",                [],                          40, 47, '',  209,  3),
    ('kds',    "Krol'dok Stronghold",       ["Krol'Dok Stronghold"],     40, 45, '',  None, 3),
    ('mara',   'Maraudon',                  [],                          45, 51, '',  349,  3),
    ('alcaz',  'Alcaz Island Prison',       ['Alcaz Prison'],            48, 53, '',  None, 3),
    ('st',     "The Temple of Atal'Hakkar", ["Temple of Atal'Hakkar", 'Sunken Temple'], 50, 55, '', 109, 3),
    ('brd',    'Blackrock Depths',          [],                          52, 60, '',  230,  3),
    ('bmh',    'Blackmaw Hold',             [],                          55, 60, '',  None, 3),
    ('brs',    'Blackrock Spire',           ['Lower Blackrock Spire', 'Upper Blackrock Spire'], 57, 60, '', 229, 3),
    ('dmaul',  'Dire Maul',                 [],                          58, 60, '',  429,  3),
    ('terrace', "Shaper's Terrace",         [],                          58, 60, '',  None, 3),
    ('strat',  'Stratholme',                [],                          58, 60, '',  329,  3),
    ('scholo', 'Scholomance',               [],                          58, 60, '',  289,  3),
]

# id, label ({n} = how many), kind, param, how many, points, min level
#   kinds: type (creature type letter, see CTYPE), elite, rare, first (first kill of a creature on the account), any
TASKS = [
    ('beast',     'Slay {n} beasts',                  'type',  'B', 30, 50, 1),
    ('humanoid',  'Slay {n} humanoids',               'type',  'H', 30, 50, 1),
    ('undead',    'Slay {n} undead',                  'type',  'U', 25, 50, 18),
    ('elemental', 'Slay {n} elementals',              'type',  'E', 15, 50, 25),
    ('demon',     'Slay {n} demons',                  'type',  'D', 15, 50, 30),
    ('elite',     'Slay {n} elites',                  'elite', '',  8,  50, 12),
    ('rare',      'Slay a rare creature',             'rare',  '',  1,  75, 10),
    ('first',     'Discover {n} new creatures',       'first', '',  5,  25, 1),
    ('any',       'Slay {n} creatures',               'any',   '',  60, 25, 1),
]
TASKS_PER_DAY = 3

# UnitCreatureType (English client) -> the one-letter code in the log
CTYPE = {'Beast': 'B', 'Humanoid': 'H', 'Undead': 'U', 'Elemental': 'E', 'Demon': 'D', 'Dragonkin': 'K',
         'Giant': 'G', 'Mechanical': 'M'}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def write_lua():
    out = ['-- Generated by tools/tcg_daily.py - do not edit by hand.',
           'HatedTCG_DAILY = {',
           f'  version = {VERSION}, dungeonPoints = {DUNGEON_POINTS}, dungeonTrash = {DUNGEON_TRASH}, perDay = {TASKS_PER_DAY},',
           '  dungeons = {']
    for k, name, alts, lo, hi, fac, mp, bosses in DUNGEONS:
        out.append(f'    {{ key = "{k}", name = {lua_str(name)}, alts = {{ {", ".join(lua_str(a) for a in alts)} }}, '
                   f'lo = {lo}, hi = {hi}, fac = "{fac}", map = {mp if mp is not None else "nil"}, bosses = {bosses} }},')
    out.append('  },')
    out.append('  tasks = {')
    for i, label, kind, param, need, pts, minl in TASKS:
        out.append(f'    {{ id = "{i}", label = {lua_str(label)}, kind = "{kind}", param = "{param}", need = {need}, points = {pts}, min = {minl} }},')
    out.append('  },')
    out.append('  ctype = { ' + ', '.join(f'[{lua_str(k)}] = "{v}"' for k, v in CTYPE.items()) + ' },')
    out.append('}')
    open(os.path.join(ROOT, 'addons/HatedCompanion/HatedTCGDailyData.lua'), 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')


def write_ts():
    data = {
        'version': VERSION, 'dungeonPoints': DUNGEON_POINTS, 'dungeonTrash': DUNGEON_TRASH, 'perDay': TASKS_PER_DAY,
        'dungeons': [dict(key=k, name=n, lo=lo, hi=hi, fac=fac, map=mp, bosses=b) for k, n, _, lo, hi, fac, mp, b in DUNGEONS],
        'tasks': [dict(id=i, label=l, kind=k, param=p, need=n, points=pts, min=m) for i, l, k, p, n, pts, m in TASKS],
    }
    body = json.dumps(data, indent=1)
    open(os.path.join(ROOT, 'supabase/functions/tcg-sync/daily_data.ts'), 'w', encoding='utf-8', newline='\n').write(
        '// Generated by tools/tcg_daily.py - do not edit by hand.\nexport const DAILY = ' + body + ' as const;\n')


if __name__ == '__main__':
    write_lua()
    write_ts()
    print(f'wrote v{VERSION}: {len(DUNGEONS)} dungeons, {len(TASKS)} tasks')
