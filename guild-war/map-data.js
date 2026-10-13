/* Guild War map: classic Azeroth + WoW: Forever additions (Riverglades, Shen'Dralas, Mount Hyjal).
   Capitals are folded into their zone (capital: true => +1 defence). Borders are land connections;
   routes are the real boat / zeppelin lines plus WoW: Forever's new sailings.
   resource: food | wood | ore | crystal. */
const WAR_ZONES = {
  // ---- Kalimdor ----
  teldrassil:      { name: 'Teldrassil',          continent: 'kalimdor', region: 'north_kalimdor', resource: 'food',    capital: 'Darnassus' },
  darkshore:       { name: 'Darkshore',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'wood' },
  ashenvale:       { name: 'Ashenvale',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'wood' },
  felwood:         { name: 'Felwood',             continent: 'kalimdor', region: 'north_kalimdor', resource: 'wood' },
  moonglade:       { name: 'Moonglade',           continent: 'kalimdor', region: 'north_kalimdor', resource: 'crystal' },
  winterspring:    { name: 'Winterspring',        continent: 'kalimdor', region: 'north_kalimdor', resource: 'crystal' },
  hyjal:           { name: 'Mount Hyjal',         continent: 'kalimdor', region: 'north_kalimdor', resource: 'crystal' },
  azshara:         { name: 'Azshara',             continent: 'kalimdor', region: 'north_kalimdor', resource: 'crystal' },
  durotar:         { name: 'Durotar',             continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food',    capital: 'Orgrimmar' },
  barrens:         { name: 'The Barrens',         continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food' },
  mulgore:         { name: 'Mulgore',             continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food',    capital: 'Thunder Bluff' },
  stonetalon:      { name: 'Stonetalon Mountains', continent: 'kalimdor', region: 'kalimdor_heart', resource: 'ore' },
  dustwallow:      { name: 'Dustwallow Marsh',    continent: 'kalimdor', region: 'kalimdor_heart', resource: 'food' },
  desolace:        { name: 'Desolace',            continent: 'kalimdor', region: 'southern_wilds', resource: 'ore' },
  shendralas:      { name: "Shen'Dralas",         continent: 'kalimdor', region: 'southern_wilds', resource: 'crystal' },
  feralas:         { name: 'Feralas',             continent: 'kalimdor', region: 'southern_wilds', resource: 'wood' },
  thousand_needles:{ name: 'Thousand Needles',    continent: 'kalimdor', region: 'southern_wilds', resource: 'ore' },
  tanaris:         { name: 'Tanaris',             continent: 'kalimdor', region: 'southern_wilds', resource: 'ore' },
  ungoro:          { name: "Un'Goro Crater",      continent: 'kalimdor', region: 'southern_wilds', resource: 'crystal' },
  silithus:        { name: 'Silithus',            continent: 'kalimdor', region: 'southern_wilds', resource: 'crystal' },
  // ---- Eastern Kingdoms ----
  tirisfal:        { name: 'Tirisfal Glades',     continent: 'eastern', region: 'lordaeron', resource: 'food',    capital: 'Undercity' },
  silverpine:      { name: 'Silverpine Forest',   continent: 'eastern', region: 'lordaeron', resource: 'wood' },
  hillsbrad:       { name: 'Hillsbrad Foothills', continent: 'eastern', region: 'lordaeron', resource: 'food' },
  alterac:         { name: 'Alterac Mountains',   continent: 'eastern', region: 'lordaeron', resource: 'ore' },
  wplaguelands:    { name: 'Western Plaguelands', continent: 'eastern', region: 'lordaeron', resource: 'food' },
  eplaguelands:    { name: 'Eastern Plaguelands', continent: 'eastern', region: 'lordaeron', resource: 'crystal' },
  hinterlands:     { name: 'The Hinterlands',     continent: 'eastern', region: 'lordaeron', resource: 'wood' },
  arathi:          { name: 'Arathi Highlands',    continent: 'eastern', region: 'khaz_modan', resource: 'food' },
  wetlands:        { name: 'Wetlands',            continent: 'eastern', region: 'khaz_modan', resource: 'food' },
  dun_morogh:      { name: 'Dun Morogh',          continent: 'eastern', region: 'khaz_modan', resource: 'ore',     capital: 'Ironforge' },
  loch_modan:      { name: 'Loch Modan',          continent: 'eastern', region: 'khaz_modan', resource: 'ore' },
  badlands:        { name: 'Badlands',            continent: 'eastern', region: 'khaz_modan', resource: 'ore' },
  searing_gorge:   { name: 'Searing Gorge',       continent: 'eastern', region: 'khaz_modan', resource: 'ore' },
  riverglades:     { name: 'Riverglades',         continent: 'eastern', region: 'khaz_modan', resource: 'food' },
  elwynn:          { name: 'Elwynn Forest',       continent: 'eastern', region: 'azeroth', resource: 'food',    capital: 'Stormwind' },
  westfall:        { name: 'Westfall',            continent: 'eastern', region: 'azeroth', resource: 'food' },
  redridge:        { name: 'Redridge Mountains',  continent: 'eastern', region: 'azeroth', resource: 'wood' },
  burning_steppes: { name: 'Burning Steppes',     continent: 'eastern', region: 'azeroth', resource: 'ore' },
  duskwood:        { name: 'Duskwood',            continent: 'eastern', region: 'azeroth', resource: 'wood' },
  stranglethorn:   { name: 'Stranglethorn Vale',  continent: 'eastern', region: 'azeroth', resource: 'wood' },
  deadwind:        { name: 'Deadwind Pass',       continent: 'eastern', region: 'azeroth', resource: 'crystal' },
  swamp_sorrows:   { name: 'Swamp of Sorrows',    continent: 'eastern', region: 'azeroth', resource: 'wood' },
  blasted_lands:   { name: 'Blasted Lands',       continent: 'eastern', region: 'azeroth', resource: 'crystal' }
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
  ['thousand_needles', 'tanaris'],
  ['tanaris', 'ungoro'],
  ['ungoro', 'silithus'],
  ['tirisfal', 'silverpine'], ['tirisfal', 'wplaguelands'],
  ['silverpine', 'hillsbrad'],
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
  { a: 'wetlands', b: 'hillsbrad',      kind: 'boat',     name: 'Menethil – Southshore ferry', forever: true },
  { a: 'hillsbrad', b: 'darkshore',     kind: 'boat',     name: 'Southshore – Auberdine ferry', forever: true },
  { a: 'tanaris', b: 'riverglades',     kind: 'boat',     name: 'Steamwheedle – Powderfuse', forever: true }
];

const WAR_REGIONS = {
  north_kalimdor: { name: 'Northern Kalimdor',  troops: 4, points: 3 },
  kalimdor_heart: { name: 'Kalimdor Heartland', troops: 3, points: 2 },
  southern_wilds: { name: 'Southern Wilds',     troops: 4, points: 3 },
  lordaeron:      { name: 'Lordaeron',          troops: 4, points: 3 },
  khaz_modan:     { name: 'Khaz Modan',         troops: 4, points: 3 },
  azeroth:        { name: 'Kingdom of Azeroth', troops: 5, points: 4 }
};

// Stronghold candidates: each week every faction gets 2 per continent from its list
const WAR_STRONGHOLDS = {
  horde:    { kalimdor: ['durotar', 'mulgore', 'barrens', 'stonetalon'],  eastern: ['tirisfal', 'hillsbrad', 'badlands', 'swamp_sorrows'] },
  alliance: { kalimdor: ['teldrassil', 'darkshore', 'ashenvale', 'dustwallow'], eastern: ['elwynn', 'dun_morogh', 'wetlands', 'redridge'] }
};

if(typeof module !== 'undefined') module.exports = { WAR_ZONES, WAR_BORDERS, WAR_ROUTES, WAR_REGIONS, WAR_STRONGHOLDS };
