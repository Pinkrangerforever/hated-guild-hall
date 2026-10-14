/* Guild War: where each zone sits on the war-table map (map space: 1308 x 1260, y down).
   Built from the WoW: Forever continent maps (Kalimdor left, Eastern Kingdoms right), stitched and muted into
   guild-war/img/war-map.jpg. guild-war/img/war-zones.png holds the zone outlines at half the map's resolution:
   each pixel is 1 + the zone's index in WAR_ZONE_ORDER, 0 = sea, 253 = land that isn't a zone, 254 = lake.
   x, y = the most inland point of the zone (where its banner stands); r = its rough radius. */
const WAR_MAP_SIZE = { w: 1308, h: 1260 };
const WAR_MAP_IMAGE = 'guild-war/img/war-map.jpg';
const WAR_ZONE_IMAGE = 'guild-war/img/war-zones.png';
const WAR_ZONE_ORDER = ["teldrassil","darkshore","felwood","hyjal","moonglade","winterspring","azshara","durotar","ashenvale","stonetalon","desolace","feralas","shendralas","barrens","mulgore","dustwallow","thousand_needles","silithus","ungoro","tanaris","eplaguelands","wplaguelands","tirisfal","silverpine","alterac","hillsbrad","hinterlands","arathi","wetlands","loch_modan","dun_morogh","badlands","burning_steppes","riverglades","elwynn","redridge","westfall","duskwood","deadwind","swamp_sorrows","blasted_lands","stranglethorn","searing_gorge"];
const WAR_LAKES = [{"x":1052,"y":659,"r":7},{"x":1060,"y":691,"r":14}];
const WAR_LAYOUT = {
  teldrassil:       { x: 164, y: 112, r: 69 },
  darkshore:        { x: 318, y: 244, r: 61 },
  felwood:          { x: 294, y: 314, r: 67 },
  hyjal:            { x: 372, y: 398, r: 81 },
  moonglade:        { x: 370, y: 244, r: 15 },
  winterspring:     { x: 456, y: 262, r: 106 },
  azshara:          { x: 492, y: 488, r: 79 },
  durotar:          { x: 468, y: 648, r: 58 },
  ashenvale:        { x: 234, y: 512, r: 93 },
  stonetalon:       { x: 222, y: 618, r: 88 },
  desolace:         { x: 130, y: 734, r: 80 },
  feralas:          { x: 178, y: 914, r: 95 },
  shendralas:       { x: 42, y: 1000, r: 33 },
  barrens:          { x: 352, y: 678, r: 113 },
  mulgore:          { x: 250, y: 786, r: 72 },
  dustwallow:       { x: 398, y: 884, r: 58 },
  thousand_needles: { x: 436, y: 986, r: 75 },
  silithus:         { x: 152, y: 1098, r: 109 },
  ungoro:           { x: 298, y: 1052, r: 81 },
  tanaris:          { x: 422, y: 1096, r: 97 },
  eplaguelands:     { x: 1110, y: 268, r: 93 },
  wplaguelands:     { x: 972, y: 268, r: 50 },
  tirisfal:         { x: 882, y: 262, r: 73 },
  silverpine:       { x: 810, y: 338, r: 56 },
  alterac:          { x: 884, y: 386, r: 58 },
  hillsbrad:        { x: 956, y: 406, r: 33 },
  hinterlands:      { x: 1030, y: 380, r: 61 },
  arathi:           { x: 1012, y: 470, r: 64 },
  wetlands:         { x: 1058, y: 590, r: 86 },
  loch_modan:       { x: 1098, y: 712, r: 53 },
  dun_morogh:       { x: 866, y: 716, r: 116 },
  badlands:         { x: 1080, y: 772, r: 41 },
  burning_steppes:  { x: 976, y: 846, r: 60 },
  riverglades:      { x: 1098, y: 856, r: 69 },
  elwynn:           { x: 866, y: 904, r: 67 },
  redridge:         { x: 1004, y: 918, r: 52 },
  westfall:         { x: 786, y: 1000, r: 55 },
  duskwood:         { x: 882, y: 1004, r: 48 },
  deadwind:         { x: 976, y: 990, r: 33 },
  swamp_sorrows:    { x: 1080, y: 976, r: 43 },
  blasted_lands:    { x: 1042, y: 1054, r: 54 },
  stranglethorn:    { x: 940, y: 1096, r: 66 },
  searing_gorge:    { x: 1008, y: 776, r: 42 }
};
if(typeof module !== 'undefined') module.exports = { WAR_MAP_SIZE, WAR_MAP_IMAGE, WAR_ZONE_IMAGE, WAR_ZONE_ORDER, WAR_LAKES, WAR_LAYOUT };
