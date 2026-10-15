/* Guild War: hand placements on the map (map px), made from the owner's notes and measured against
   each zone's real outline. pieces = where the banner / stronghold stands; labels = [x, y, font size?];
   icons = resource icon; holds = stronghold turn (radians) / scale / at (where the building stands, map px); mountains, landmarks = cluster centres. */
const WAR_TUNING = {
  "pieces": {
   "darkshore": [
    232,
    306
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
    290,
    510
   ],
   "durotar": [
    490,
    596
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
   "redridge": [
    1028,
    936
   ],
   "riverglades": [
    1124,
    888
   ],
   "wetlands": [
    1048,
    572
   ],
   "badlands": [
    1084,
    772
   ],
   "arathi": [
    1030,
    454
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
    310,
    298
   ],
   "hyjal": [
    370,
    404
   ],
   "ashenvale": [
    336,
    544,
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
   "badlands": [
    1084,
    774
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
    "scale": 0.9,
    "at": [1018, 906]
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
  },
  "zeppelins": [
   [
    496,
    627
   ],
   [
    880,
    1102
   ],
   [
    837,
    224
   ]
  ]
};
if(typeof module !== 'undefined') module.exports = { WAR_TUNING };
