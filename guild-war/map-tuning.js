/* Guild War: hand placements on the map (map px), made from the owner's notes and measured against
   each zone's real outline. pieces = where the banner / stronghold stands; labels = [x, y, font size?];
   icons = resource icon; holds = stronghold turn (radians) / scale; mountains, landmarks = cluster centres. */
const WAR_TUNING = {
  "pieces": {
   "darkshore": [
    250,
    294
   ],
   "felwood": [
    278,
    364
   ],
   "hyjal": [
    318,
    384
   ],
   "ashenvale": [
    294,
    482
   ],
   "durotar": [
    476,
    570
   ],
   "mulgore": [
    266,
    726
   ],
   "stranglethorn": [
    940,
    1066
   ],
   "duskwood": [
    894,
    976
   ],
   "swamp_sorrows": [
    1084,
    960
   ],
   "blasted_lands": [
    1036,
    1022
   ],
   "riverglades": [
    1124,
    888
   ],
   "wetlands": [
    1048,
    638
   ],
   "arathi": [
    1052,
    430
   ],
   "hinterlands": [
    1030,
    354
   ],
   "silverpine": [
    782,
    324
   ],
   "tirisfal": [
    882,
    284
   ]
  },
  "labels": {
   "teldrassil": [
    150,
    158
   ],
   "winterspring": [
    450,
    288
   ],
   "felwood": [
    288,
    298
   ],
   "hyjal": [
    370,
    404
   ],
   "ashenvale": [
    290,
    518,
    26
   ],
   "stonetalon": [
    174,
    588,
    24
   ],
   "thousand_needles": [
    376,
    960,
    24
   ],
   "duskwood": [
    898,
    1000
   ],
   "blasted_lands": [
    1036,
    1056
   ],
   "riverglades": [
    1124,
    842
   ],
   "loch_modan": [
    1070,
    678
   ],
   "wetlands": [
    1048,
    606
   ],
   "arathi": [
    1052,
    466
   ],
   "hinterlands": [
    1076,
    384
   ],
   "silverpine": [
    814,
    350
   ],
   "eplaguelands": [
    1108,
    266
   ]
  },
  "icons": {
   "winterspring": [
    450,
    322
   ],
   "hyjal": [
    370,
    438
   ],
   "stonetalon": [
    182,
    646
   ],
   "blasted_lands": [
    1036,
    1086
   ],
   "loch_modan": [
    1066,
    722
   ],
   "eplaguelands": [
    1108,
    300
   ]
  },
  "holds": {
   "swamp_sorrows": {
    "rot": -0.785
   },
   "redridge": {
    "scale": 0.65
   }
  },
  "mountains": {
   "stonetalon": [
    128,
    534
   ]
  },
  "landmarks": {
   "burning_steppes": [
    914,
    808
   ]
  }
};
if(typeof module !== 'undefined') module.exports = { WAR_TUNING };
