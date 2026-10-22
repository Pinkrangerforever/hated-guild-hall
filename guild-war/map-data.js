/* Guild War map: classic Azeroth + WoW: Forever additions (Riverglades, Shen'Dralas, Mount Hyjal).
   Capitals are folded into their zone (capital: true => +1 defence). Borders are land connections;
   routes are the real boat / zeppelin lines plus WoW: Forever's new sailings.
   resource: food | wood | ore | gold - dealt so no two bordering zones share one, ~even per continent. */
const WAR_ZONES = {
  // ---- Kalimdor ----
  teldrassil:      { name: 'Teldrassil',          continent: 'kalimdor', region: 'north_kalimdor', resource: 'food',    capital: 'Darnassus' },
  darkshore:       { name: 'Darkshore',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'ore' },
  ashenvale:       { name: 'Ashenvale',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'wood' },
  felwood:         { name: 'Felwood',             continent: 'kalimdor', region: 'north_kalimdor', resource: 'food' },
  moonglade:       { name: 'Moonglade',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'wood' },
  winterspring:    { name: 'Winterspring',        continent: 'kalimdor', region: 'north_kalimdor', resource: 'gold' },
  hyjal:           { name: 'Mount Hyjal',         continent: 'kalimdor', region: 'north_kalimdor', resource: 'ore' },
  azshara:         { name: 'Azshara',             continent: 'kalimdor', region: 'north_kalimdor', resource: 'food' },
  durotar:         { name: 'Durotar',             continent: 'kalimdor', region: 'kalimdor_heart', resource: 'wood',    capital: 'Orgrimmar' },
  barrens:         { name: 'The Barrens',         continent: 'kalimdor', region: 'kalimdor_heart', resource: 'gold' },
  mulgore:         { name: 'Mulgore',             continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food',    capital: 'Thunder Bluff' },
  stonetalon:      { name: 'Stonetalon Mountains', continent: 'kalimdor', region: 'kalimdor_heart', resource: 'ore' },
  dustwallow:      { name: 'Dustwallow Marsh',    continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food' },
  desolace:        { name: 'Desolace',            continent: 'kalimdor', region: 'kalimdor_heart', resource: 'gold' },
  shendralas:      { name: "Shen'Dralas",         continent: 'kalimdor', region: 'southern_wilds', resource: 'ore' },
  feralas:         { name: 'Feralas',             continent: 'kalimdor', region: 'southern_wilds', resource: 'wood' },
  thousand_needles:{ name: 'Thousand Needles',    continent: 'kalimdor', region: 'southern_wilds', resource: 'ore' },
  tanaris:         { name: 'Tanaris',             continent: 'kalimdor', region: 'southern_wilds', resource: 'gold' },
  ungoro:          { name: "Un'Goro Crater",      continent: 'kalimdor', region: 'southern_wilds', resource: 'wood' },
  silithus:        { name: 'Silithus',            continent: 'kalimdor', region: 'southern_wilds', resource: 'gold' },
  // ---- Eastern Kingdoms ----
  tirisfal:        { name: 'Tirisfal Glades',     continent: 'eastern', region: 'lordaeron', resource: 'food',    capital: 'Undercity' },
  silverpine:      { name: 'Silverpine Forest',   continent: 'eastern', region: 'lordaeron', resource: 'wood' },
  hillsbrad:       { name: 'Hillsbrad Foothills', continent: 'eastern', region: 'lordaeron', resource: 'food' },
  alterac:         { name: 'Alterac Mountains',   continent: 'eastern', region: 'lordaeron', resource: 'ore' },
  wplaguelands:    { name: 'Western Plaguelands', continent: 'eastern', region: 'lordaeron', resource: 'wood' },
  eplaguelands:    { name: 'Eastern Plaguelands', continent: 'eastern', region: 'lordaeron', resource: 'gold' },
  hinterlands:     { name: 'The Hinterlands',     continent: 'eastern', region: 'lordaeron', resource: 'wood' },
  arathi:          { name: 'Arathi Highlands',    continent: 'eastern', region: 'khaz_modan', resource: 'ore' },
  wetlands:        { name: 'Wetlands',            continent: 'eastern', region: 'khaz_modan', resource: 'food' },
  dun_morogh:      { name: 'Dun Morogh',          continent: 'eastern', region: 'khaz_modan', resource: 'ore',     capital: 'Ironforge' },
  loch_modan:      { name: 'Loch Modan',          continent: 'eastern', region: 'khaz_modan', resource: 'gold' },
  badlands:        { name: 'Badlands',            continent: 'eastern', region: 'khaz_modan', resource: 'ore' },
  searing_gorge:   { name: 'Searing Gorge',       continent: 'eastern', region: 'khaz_modan', resource: 'wood' },
  riverglades:     { name: 'Riverglades',         continent: 'eastern', region: 'azeroth', resource: 'food' },
  elwynn:          { name: 'Elwynn Forest',       continent: 'eastern', region: 'khaz_modan', resource: 'food',    capital: 'Stormwind' },
  westfall:        { name: 'Westfall',            continent: 'eastern', region: 'azeroth', resource: 'gold' },
  redridge:        { name: 'Redridge Mountains',  continent: 'eastern', region: 'azeroth', resource: 'ore' },
  burning_steppes: { name: 'Burning Steppes',     continent: 'eastern', region: 'khaz_modan', resource: 'gold' },
  duskwood:        { name: 'Duskwood',            continent: 'eastern', region: 'azeroth', resource: 'wood' },
  stranglethorn:   { name: 'Stranglethorn Vale',  continent: 'eastern', region: 'azeroth', resource: 'food' },
  deadwind:        { name: 'Deadwind Pass',       continent: 'eastern', region: 'azeroth', resource: 'gold' },
  swamp_sorrows:   { name: 'Swamp of Sorrows',    continent: 'eastern', region: 'azeroth', resource: 'wood' },
  blasted_lands:   { name: 'Blasted Lands',       continent: 'eastern', region: 'azeroth', resource: 'ore' }
};

// Land borders (each pair listed once)
const WAR_BORDERS = [
  ['teldrassil', 'darkshore'],   // Rut'theran: a short hop, treated as land
  ['darkshore', 'ashenvale'],
  ['ashenvale', 'felwood'], ['ashenvale', 'azshara'], ['ashenvale', 'stonetalon'], ['ashenvale', 'barrens'],
  ['felwood', 'moonglade'], ['felwood', 'winterspring'],
  ['moonglade', 'winterspring'],
  ['winterspring', 'hyjal'],
  ['stonetalon', 'barrens'], ['stonetalon', 'desolace'],
  ['desolace', 'feralas'], ['desolace', 'shendralas'],
  ['feralas', 'thousand_needles'],
  ['durotar', 'barrens'],
  ['barrens', 'mulgore'], ['barrens', 'thousand_needles'], ['barrens', 'dustwallow'],
  ['mulgore', 'stonetalon'],      // added 2026-10-22: up out of Mulgore into Stonetalon
  ['shendralas', 'feralas'],     // added 2026-10-22: down from Shen'Dralas into Feralas
  ['thousand_needles', 'tanaris'],
  ['tanaris', 'ungoro'],
  ['ungoro', 'silithus'],
  ['tirisfal', 'silverpine'], ['tirisfal', 'wplaguelands'],
  ['silverpine', 'hillsbrad'], ['silverpine', 'alterac'],   // across Lordamere Lake's east shore
  ['hillsbrad', 'alterac'], ['hillsbrad', 'arathi'], ['hillsbrad', 'hinterlands'],
  ['alterac', 'wplaguelands'],
  ['wplaguelands', 'eplaguelands'],
  ['arathi', 'wetlands'],
  ['wetlands', 'dun_morogh'], ['wetlands', 'loch_modan'],
  ['dun_morogh', 'loch_modan'],
  ['loch_modan', 'badlands'],
  ['badlands', 'searing_gorge'], ['badlands', 'riverglades'],
  ['searing_gorge', 'burning_steppes'],
  ['burning_steppes', 'redridge'], ['burning_steppes', 'riverglades'],
  ['redridge', 'elwynn'], ['redridge', 'duskwood'], ['redridge', 'riverglades'],
  ['elwynn', 'westfall'], ['elwynn', 'duskwood'],
  ['westfall', 'duskwood'],
  ['duskwood', 'stranglethorn'], ['duskwood', 'deadwind'],
  ['deadwind', 'swamp_sorrows'],
  ['swamp_sorrows', 'blasted_lands']
];

// Sea and air routes (count as borders for moving and attacking)
const WAR_ROUTES = [
  { a: 'darkshore', b: 'wetlands',      kind: 'boat',     name: 'Auberdine – Menethil' },
  { a: 'dustwallow', b: 'wetlands',     kind: 'boat',     name: 'Theramore – Menethil' },
  { a: 'barrens', b: 'stranglethorn',   kind: 'boat',     name: 'Ratchet – Booty Bay' },
  { a: 'durotar', b: 'tirisfal',        kind: 'zeppelin', name: 'Orgrimmar – Undercity' },
  { a: 'durotar', b: 'stranglethorn',   kind: 'zeppelin', name: "Orgrimmar – Grom'gol" },
  { a: 'tirisfal', b: 'stranglethorn',  kind: 'zeppelin', name: "Undercity – Grom'gol" },
  { a: 'elwynn', b: 'darkshore',        kind: 'boat',     name: 'Stormwind Harbor – Auberdine', forever: true },
  { a: 'hillsbrad', b: 'darkshore',     kind: 'boat',     name: 'Southshore – Auberdine ferry', forever: true },
  { a: 'tanaris', b: 'riverglades',     kind: 'boat',     name: 'Steamwheedle – Powderfuse', forever: true }
];

const WAR_REGIONS = {
  north_kalimdor: { name: 'Northern Kalimdor',  troops: 5, points: 4, color: '#3f9a5a' },
  kalimdor_heart: { name: 'Kalimdor Heartland', troops: 3, points: 2, color: '#c0612b' },
  southern_wilds: { name: 'Southern Wilds',     troops: 3, points: 2, color: '#d6b13a' },
  lordaeron:      { name: 'Lordaeron',          troops: 4, points: 3, color: '#8a5fc0' },
  khaz_modan:     { name: 'The Heartlands',      troops: 5, points: 4, color: '#3a7fd0' },
  azeroth:        { name: 'Southern Kingdoms',  troops: 5, points: 4, color: '#c03a4a' }
};

// Stronghold candidates: each week every faction gets 2 per continent from its list
const WAR_STRONGHOLDS = {
  horde:    { kalimdor: ['durotar', 'mulgore', 'barrens', 'stonetalon'],  eastern: ['tirisfal', 'hillsbrad', 'badlands', 'swamp_sorrows'] },
  alliance: { kalimdor: ['teldrassil', 'darkshore', 'ashenvale', 'dustwallow'], eastern: ['elwynn', 'dun_morogh', 'wetlands', 'redridge'] }
};

if(typeof module !== 'undefined') module.exports = { WAR_ZONES, WAR_BORDERS, WAR_ROUTES, WAR_REGIONS, WAR_STRONGHOLDS };
