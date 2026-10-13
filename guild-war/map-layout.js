/* Guild War: where each zone sits on the war-table map (map space: 2000 x 1200, y down).
   Hand-placed after the WoW world map. The board builds the land from these points: every pixel near a
   point is land, and it belongs to the nearest point (so zone shapes are generated, not drawn).
   r = how far that zone's land reaches (bigger zones get more). */
const WAR_MAP_SIZE = { w: 2000, h: 1200 };
const WAR_LAYOUT = {
  // ---- Kalimdor (left) ----
  teldrassil:       { x: 205, y: 115, r: 82 },
  darkshore:        { x: 335, y: 275, r: 92 },
  moonglade:        { x: 470, y: 175, r: 62 },
  hyjal:            { x: 610, y: 95,  r: 74 },
  winterspring:     { x: 640, y: 215, r: 96 },
  felwood:          { x: 455, y: 300, r: 82 },
  azshara:          { x: 705, y: 355, r: 92 },
  ashenvale:        { x: 470, y: 415, r: 104 },
  stonetalon:       { x: 310, y: 470, r: 86 },
  durotar:          { x: 665, y: 525, r: 82 },
  barrens:          { x: 520, y: 610, r: 112 },
  mulgore:          { x: 390, y: 650, r: 84 },
  desolace:         { x: 225, y: 625, r: 92 },
  shendralas:       { x: 130, y: 515, r: 74 },
  dustwallow:       { x: 655, y: 760, r: 86 },
  feralas:          { x: 240, y: 820, r: 104 },
  thousand_needles: { x: 465, y: 850, r: 92 },
  tanaris:          { x: 610, y: 965, r: 104 },
  ungoro:           { x: 445, y: 995, r: 82 },
  silithus:         { x: 290, y: 1030, r: 92 },
  // ---- Eastern Kingdoms (right) ----
  tirisfal:         { x: 1345, y: 165, r: 92 },
  wplaguelands:     { x: 1490, y: 200, r: 86 },
  eplaguelands:     { x: 1655, y: 190, r: 96 },
  silverpine:       { x: 1275, y: 300, r: 86 },
  alterac:          { x: 1430, y: 315, r: 70 },
  hinterlands:      { x: 1620, y: 345, r: 92 },
  hillsbrad:        { x: 1385, y: 410, r: 84 },
  arathi:           { x: 1545, y: 445, r: 86 },
  wetlands:         { x: 1510, y: 565, r: 86 },
  dun_morogh:       { x: 1400, y: 660, r: 92 },
  loch_modan:       { x: 1570, y: 655, r: 76 },
  searing_gorge:    { x: 1470, y: 760, r: 68 },
  badlands:         { x: 1605, y: 765, r: 80 },
  burning_steppes:  { x: 1500, y: 855, r: 76 },
  riverglades:      { x: 1700, y: 865, r: 86 },
  elwynn:           { x: 1395, y: 935, r: 84 },
  redridge:         { x: 1575, y: 940, r: 70 },
  westfall:         { x: 1295, y: 1010, r: 76 },
  duskwood:         { x: 1440, y: 1025, r: 78 },
  deadwind:         { x: 1555, y: 1040, r: 56 },
  swamp_sorrows:    { x: 1650, y: 1010, r: 70 },
  blasted_lands:    { x: 1680, y: 1115, r: 76 },
  stranglethorn:    { x: 1385, y: 1125, r: 94 }
};
if(typeof module !== 'undefined') module.exports = { WAR_MAP_SIZE, WAR_LAYOUT };
