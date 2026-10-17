/* Guild War board: the war room, the table, the map, the pieces on it, the camera and the battle animations.
   The map is the WoW: Forever continents (guild-war/img/war-map.jpg); guild-war/img/war-zones.png says which
   zone each pixel belongs to (see map-layout.js). Map space (MW x MH, y down) -> table space: the map is
   PW x PH world units centred on the table, table top at y = 0. */
(function(){
  const MW = WAR_MAP_SIZE.w, MH = WAR_MAP_SIZE.h;
  const PW = 8.2, PH = PW * MH / MW;              // the map's size on the table (fits inside the round top)
  const KEYS = Object.keys(WAR_LAYOUT);
  const COL = {
    horde: [178, 34, 28], alliance: [36, 84, 190], neutral: [120, 110, 92],
    hordeHex: 0xb3221c, allianceHex: 0x2454be, neutralHex: 0x8a7f6a
  };
  const toWorld = (x, y) => new THREE.Vector3((x / MW - 0.5) * PW, 0, (y / MH - 0.5) * PH);
  // scenery pieces standing on the map (map-px offsets from the zone's anchor); zones with scenery in the
  // middle move their banner / stronghold aside (PIECE_SHIFT)
  const SCENERY = {
    teldrassil: { model: 'tree', dx: 14, dy: -6 },
    hyjal:      { model: 'tree', dx: 10, dy: -12 }
  };
  const SCENERY_MODELS = { tree: { url: 'models/war/world-tree.gltf', height: 0.48, mask: /branch/i } };
  const PIECE_SHIFT = { teldrassil: [-26, 6], hyjal: [-38, 12] };
  const TUNE = typeof WAR_TUNING !== 'undefined' ? WAR_TUNING : { pieces: {}, labels: {}, icons: {}, holds: {}, mountains: {}, landmarks: {} };   // map-tuning.js
  const anchor = k => { if(TUNE.pieces[k]) return TUNE.pieces[k].slice(0, 2); const p = WAR_LAYOUT[k], s = PIECE_SHIFT[k] || [0, 0]; return [p.x + s[0], p.y + s[1]]; };
  const zoneWorld = k => toWorld(...anchor(k));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // which monsters hold the neutral camps in each region (regions without one use plain tokens)
  // pets are sized by stage, measured by footprint (the larger of length and wingspan) in the zone's piece space
  const PET_SPAN = { juvenile: 0.3, adult: 0.6, boss: 0.95 };
  const NEUTRAL_MOBS = { khaz_modan: 'mob_gnoll', kalimdor_heart: 'mob_centaur', southern_wilds: 'mob_silithid', north_kalimdor: 'mob_furbolg', lordaeron: 'mob_ghoul', azeroth: 'mob_defias' };
  // the clip each animation request uses, in order of preference (monsters have no weapon stances)
  const CLIP_ALIASES = { Ready1H: ['Ready1H', 'ReadyUnarmed', 'Stand'], Attack1H: ['Attack1H', 'AttackUnarmed'], BattleRoar: ['BattleRoar', 'AttackUnarmed', 'Attack1H'], Run: ['Run'], Death: ['Death'], Stand: ['Stand', 'Ready1H'] };
  const ease = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  const easeOut = t => 1 - Math.pow(1 - t, 3);
  // raster values: 1 + index in WAR_ZONE_ORDER; 0 sea, 253 land that isn't a zone, 254 lake
  const SEA = 0, WASTE = 253, LAKE = 254;
  const isZone = v => v > 0 && v < WASTE;
  // mountains rise in these zones (little 3D peaks); 1 = snow caps
  // board mountains: clusters of the WoW mountain model at mixed sizes, clipping into each other.
  // count = how many peaks, size = tallest peak (world units), snow = white caps
  const MOUNTAINS = {
    stonetalon:   { count: 5, size: 0.26, snow: false },
    winterspring: { count: 3, size: 0.22, snow: true },
    alterac:      { count: 3, size: 0.2,  snow: true },
    dun_morogh:   { count: 3, size: 0.22, snow: true }
  };
  const LANDMARKS = { burning_steppes: { model: 'volcano', size: 0.22, side: -0.62 } };   // Blackrock Mountain, on the zone's left side (side = fraction of the zone's radius)
  const TERRAIN_MODELS = {
    mountain: { url: 'models/war/mountain.gltf', tint: 0x8d7a66 },   // its texture is pale stone: warm it so snow caps read
    volcano:  { url: 'models/war/blackrock-mountain.gltf', glow: /lava/i }
  };

  // the map's edges curl up like old parchment
  const CURL_BAND = 0.07, CURL_LIFT = 0.28;
  // only the top-left and bottom-right corners curl (uv: v = 1 is the top edge)
  const CURL_R = 0.16;
  function curlHeight(u, v){
    const corner = (du, dv) => { const d = Math.hypot(du, dv * MH / MW); return d < CURL_R ? Math.pow((CURL_R - d) / CURL_R, 2) : 0; };
    return Math.max(corner(u, 1 - v), corner(1 - u, v)) * CURL_LIFT * 1.6;
  }

  // ---------- small canvas textures ----------
  function canvasTex(w, h, draw){
    const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h);
    const t = new THREE.CanvasTexture(c); t.anisotropy = 4; return t;
  }
  function woodTex(base, dark){
    return canvasTex(512, 512, (g, w, h) => {
      g.fillStyle = base; g.fillRect(0, 0, w, h);
      for(let i = 0; i < 140; i++){
        g.strokeStyle = `rgba(${dark},${0.08 + Math.random() * 0.18})`; g.lineWidth = 1 + Math.random() * 3;
        const y = Math.random() * h; g.beginPath(); g.moveTo(0, y);
        for(let x = 0; x <= w; x += 32) g.lineTo(x, y + Math.sin(x / 60 + i) * 4 + (Math.random() - 0.5) * 2);
        g.stroke();
      }
    });
  }
  function stoneTex(){
    return canvasTex(512, 512, (g, w, h) => {
      g.fillStyle = '#3a342d'; g.fillRect(0, 0, w, h);
      const rows = 8;
      for(let r = 0; r < rows; r++){
        const bh = h / rows, off = (r % 2) * 40;
        for(let x = -off; x < w; x += 80){
          const v = 50 + Math.random() * 25;
          g.fillStyle = `rgb(${v + 8},${v + 2},${v - 6})`;
          g.fillRect(x + 3, r * bh + 3, 74, bh - 6);
        }
      }
    });
  }
  function glowTex(){
    return canvasTex(128, 128, (g) => {
      const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
      gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.3, 'rgba(255,255,255,0.5)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
    });
  }
  function dieFaceTex(n, bg, pip, trim){
    return canvasTex(256, 256, (g) => {
      const body = g.createRadialGradient(110, 100, 20, 128, 128, 190);
      body.addColorStop(0, shade(bg, 1.25)); body.addColorStop(0.7, bg); body.addColorStop(1, shade(bg, 0.6));
      g.fillStyle = body; g.fillRect(0, 0, 256, 256);
      // faint grain so it reads as bone / lacquered wood, not plastic
      for(let i = 0; i < 260; i++){ g.fillStyle = `rgba(255,255,255,${Math.random() * 0.05})`; g.fillRect(Math.random() * 256, Math.random() * 256, 1 + Math.random() * 3, 1); }
      // gilt inlay border
      g.strokeStyle = trim; g.lineWidth = 7; g.globalAlpha = 0.9; roundRect(g, 18, 18, 220, 220, 26); g.stroke();
      g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 2; roundRect(g, 25, 25, 206, 206, 22); g.stroke(); g.globalAlpha = 1;
      const P = { 1: [[128, 128]], 2: [[78, 78], [178, 178]], 3: [[72, 72], [128, 128], [184, 184]], 4: [[78, 78], [178, 78], [78, 178], [178, 178]],
                  5: [[74, 74], [182, 74], [128, 128], [74, 182], [182, 182]], 6: [[80, 66], [176, 66], [80, 128], [176, 128], [80, 190], [176, 190]] }[n];
      const r = n === 1 ? 30 : 21;
      P.forEach(([x, y]) => {
        g.fillStyle = 'rgba(255,255,255,0.35)'; g.beginPath(); g.arc(x + 2, y + 3, r + 2, 0, Math.PI * 2); g.fill();      // lit lower rim
        const hole = g.createRadialGradient(x - r * 0.35, y - r * 0.35, 1, x, y, r);
        hole.addColorStop(0, shade(pip, 0.55)); hole.addColorStop(0.75, pip); hole.addColorStop(1, shade(pip, 1.25));
        g.fillStyle = hole; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
        g.strokeStyle = 'rgba(0,0,0,0.5)'; g.lineWidth = 2; g.beginPath(); g.arc(x, y, r, Math.PI * 1.05, Math.PI * 1.95); g.stroke();   // shadowed upper lip
      });
    });
  }
  function shade(hex, k){
    const v = parseInt(hex.slice(1), 16), c = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map(x => Math.max(0, Math.min(255, Math.round(x * k))));
    return '#' + c.map(x => x.toString(16).padStart(2, '0')).join('');
  }
  function roundRect(g, x, y, w, h, r){ g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
  // a cube with rounded edges: a subdivided box whose vertices are pulled onto a rounded shell
  function roundedBox(size, radius, seg){
    const g = new THREE.BoxGeometry(size, size, size, seg, seg, seg), pos = g.attributes.position, h = size / 2 - radius, v = new THREE.Vector3(), c = new THREE.Vector3();
    for(let i = 0; i < pos.count; i++){
      v.fromBufferAttribute(pos, i); c.set(Math.max(-h, Math.min(h, v.x)), Math.max(-h, Math.min(h, v.y)), Math.max(-h, Math.min(h, v.z)));
      v.sub(c).normalize().multiplyScalar(radius).add(c); pos.setXYZ(i, v.x, v.y, v.z);
    }
    g.computeVertexNormals(); return g;
  }


  // ---------- board ----------
  class WarBoard {
    constructor(container, opts){
      this.el = container; this.opts = opts || {};
      this.speed = 1; this.state = null; this.selected = null; this.anims = []; this.labels = {};
      this.raster = null; this.RW = 1; this.RH = 1;   // zone outlines, loaded with the map image
      this.zoneVal = {}; WAR_ZONE_ORDER.forEach((k, i) => { this.zoneVal[k] = i + 1; });
      this.renderer = new THREE.WebGLRenderer({ antialias: true });
      this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
      this.renderer.shadowMap.enabled = true; this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
      this.renderer.outputEncoding = THREE.sRGBEncoding;
      container.appendChild(this.renderer.domElement);
      this.overlay = document.createElement('div'); this.overlay.className = 'wb-overlay'; container.appendChild(this.overlay);
      this.scene = new THREE.Scene(); this.scene.background = new THREE.Color(0x0b0806); this.scene.fog = new THREE.Fog(0x0b0806, 16, 34);
      this.camera = new THREE.PerspectiveCamera(42, 1, 0.05, 80);
      this.cam = { target: new THREE.Vector3(0, 0.5, -2), dist: 17, polar: 1.32, az: 0 }; this.shakeOff = new THREE.Vector3();
      this._loading = 0;
      const LM = THREE.DefaultLoadingManager, prevStart = LM.onStart, prevProg = LM.onProgress;
      LM.onStart = (u, l, t) => { this._loading = t - l; prevStart && prevStart(u, l, t); };
      LM.onProgress = (u, l, t) => { this._loading = t - l; prevProg && prevProg(u, l, t); };
      LM.onError = () => {};
      this.glow = glowTex();
      this.buildRoom(); this.loadTable(); this.loadStrongholds(); this.loadFlags(); this.loadScenery(); this.loadTerrainModels(); this.loadSnowman(); this.loadDoorway(); this.loadSuccubus(); this.loadPainting(); this.loadShips(); this.loadTroops(); this.loadCandles(); this.loadHordeFortify(); this.loadEggs(); this.buildMap(); this.buildDice();
      this.pieces = {}; KEYS.forEach(k => { this.pieces[k] = this.buildPiece(k); });
      this.raycaster = new THREE.Raycaster(); this.mouse = new THREE.Vector2();
      this.bindInput();
      this.resize(); window.addEventListener('resize', () => this.resize());
      this.clock = performance.now();
      const loop = () => { requestAnimationFrame(loop); this.tick(); };
      loop();
    }

    // ----- room -----
    buildRoom(){
      const S = this.scene;
      S.add(new THREE.HemisphereLight(0xffd8a0, 0x1a1008, 0.35));
      const key = new THREE.SpotLight(0xffe2b0, 1.25, 30, 0.62, 0.55, 1.2);
      key.position.set(0, 11, 2); key.target.position.set(0, 0, 0); key.castShadow = true;
      key.shadow.mapSize.set(2048, 2048); key.shadow.bias = -0.0004;
      S.add(key, key.target); this.keyLight = key;
      // ---- the hall: an eight-sided orc garrison keep with a snowy doorway at the back ----
      const R2W = window.WAR_TEX_BASE || 'https://assets.hatedforever.com/War%20Games/';
      const tl = new THREE.TextureLoader(); tl.setCrossOrigin('anonymous');
      const tex = (f, rx, ry) => { const t = tl.load(R2W + f + '.png'); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rx, ry); t.encoding = THREE.sRGBEncoding; t.anisotropy = 8; return t; };
      const A = 15, SIDE = 2 * A * Math.tan(Math.PI / 8), FLOOR_Y = -3.1, WALL_H = 17, TILE = 2.6;   // apothem, wall width, tile size
      const RC = A / Math.cos(Math.PI / 8);
      // floor: octagon of garrison planks
      const floor = new THREE.Mesh(new THREE.CircleGeometry(RC, 8, Math.PI / 8), new THREE.MeshStandardMaterial({ map: tex('6or_garrison_woodfloor', RC / 1.6, RC / 1.6), roughness: 0.85   /* tile = 3.2 units */ }));
      floor.rotation.x = -Math.PI / 2; floor.position.y = FLOOR_Y; floor.receiveShadow = true; S.add(floor); this.floor = floor;
      // walls: plain stonework, the back wall frosted with snow round an open doorway
      this.walls = new THREE.Group(); this.walls.position.y = FLOOR_Y; S.add(this.walls);
      const wallMat = (f, w, h) => new THREE.MeshStandardMaterial({ map: tex(f, w / TILE, h / TILE), roughness: 0.95 });
      const DOOR_W = 4.1, DOOR_H = 5.2;   // fits the Shadowfang door (3.96 x 5.04 model units, scaled 1.03)
      for(let i = 0; i < 8; i++){
        const a = i * Math.PI / 4, wall = new THREE.Group();
        wall.position.set(A * Math.sin(a), 0, -A * Math.cos(a)); wall.rotation.y = -a; this.walls.add(wall);
        const piece = (f, w, h, x, y) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), wallMat(f, w, h)); m.position.set(x, y + h / 2, 0); m.receiveShadow = true; wall.add(m); return m; };
        if(i === 0){
          const sw = (SIDE - DOOR_W) / 2;
          piece('6or_garrison_stonewall_snow', sw, WALL_H, -(DOOR_W + sw) / 2, 0);
          piece('6or_garrison_stonewall_snow', sw, WALL_H, (DOOR_W + sw) / 2, 0);
          piece('6or_garrison_stonewall_snow', DOOR_W, WALL_H - DOOR_H, 0, DOOR_H);
          // a timber door frame
          // frame cut from the Shadowfang door's own textures so it matches the door
          const DT = 'https://assets.hatedforever.com/War%20Games/War%20Room/Door/';
          const dtex = (f, rx, ry) => { const t = tl.load(DT + f + '.png'); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rx, ry); t.encoding = THREE.sRGBEncoding; return t; };
          const jamb = new THREE.MeshStandardMaterial({ map: dtex('127757', 0.25, 2.2), roughness: 0.85 });
          const lintel = new THREE.MeshStandardMaterial({ map: dtex('129746', 1.6, 0.25), roughness: 0.7, metalness: 0.15 });
          [[-DOOR_W / 2 - 0.15, DOOR_H / 2, 0.45, DOOR_H, jamb], [DOOR_W / 2 + 0.15, DOOR_H / 2, 0.45, DOOR_H, jamb], [0, DOOR_H + 0.25, DOOR_W + 1.0, 0.55, lintel]].forEach(([x, y, w, h, mat]) => {
            const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, 0.5), mat); m.position.set(x, y, 0.12); m.castShadow = true; wall.add(m);
            (this.doorFrameParts = this.doorFrameParts || []).push(m);
          });
          this.doorWall = wall; this.doorFrameMat = jamb; this.doorStoneTex = tex('6or_garrison_stonewall_snow', 1 / TILE, 1 / TILE); this.doorSize = [DOOR_W, DOOR_H]; this.doorTex = dtex;
          // the door is pointed: a planked header fills the doorway's top corners behind it
          const header = new THREE.Mesh(new THREE.BoxGeometry(DOOR_W, 1.3, 0.12), new THREE.MeshStandardMaterial({ map: dtex('127757', 1.4, 0.4), roughness: 0.85 }));
          header.position.set(0, DOOR_H - 0.65, -0.25); wall.add(header); this.doorFrameParts.push(header);
        } else piece('6or_garrison_stonewall', SIDE, WALL_H, 0, 0);
        // a skirting of dark stone where the wall meets the floor
        const skirt = new THREE.Mesh(new THREE.BoxGeometry(SIDE, 0.5, 0.25), new THREE.MeshStandardMaterial({ map: tex('6or_garrison_stonewall', SIDE / TILE, 0.2), color: 0x77706a, roughness: 1 }));
        skirt.position.set(0, 0.25, 0.12); if(i !== 0) wall.add(skirt);   // the doorway wall has no skirting
      }
      // corners: a stone pillar faced with the red-cloth-and-post stonework at each of the 8 corners
      // plain stone up to a cap faced with the red-cloth-and-post stonework (one band, not repeated)
      const CAP = 2.2, pillarBody = new THREE.MeshStandardMaterial({ map: tex('6or_garrison_stonewall', 0.8, (WALL_H - CAP) / TILE), color: 0x958a80, roughness: 0.95 });
      const pillarCap = new THREE.MeshStandardMaterial({ map: tex('6or_garrison_stonewall2', 1, 1), roughness: 0.9 });
      for(let i = 0; i < 8; i++){
        const a = i * Math.PI / 4 + Math.PI / 8, px = RC * 0.95 * Math.sin(a), pz = -RC * 0.95 * Math.cos(a);   // stands well out of the corner
        const body = new THREE.Mesh(new THREE.BoxGeometry(2, WALL_H - CAP, 1.6), pillarBody);
        body.position.set(px, (WALL_H - CAP) / 2, pz); body.rotation.y = -a; body.castShadow = body.receiveShadow = true; this.walls.add(body);
        const cap = new THREE.Mesh(new THREE.BoxGeometry(2.2, CAP, 1.8), pillarCap);
        cap.position.set(px, WALL_H - CAP / 2 - 1.2, pz); cap.rotation.y = -a; cap.castShadow = true; this.walls.add(cap);
      }
      // ceiling beams fading into the dark
      const beamMat = new THREE.MeshStandardMaterial({ map: tex('6or_garrison_woodfloor', 0.3, 4), color: 0x8a7a68, roughness: 0.9 });
      for(let i = 0; i < 4; i++){
        const beam = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.7, RC * 2), beamMat);
        beam.position.y = WALL_H - 0.6; beam.rotation.y = i * Math.PI / 4; this.walls.add(beam);
      }
      // outside the doorway: a cold night, falling snow, snow blown in across the planks
      const night = new THREE.Mesh(new THREE.PlaneGeometry(DOOR_W + 1, DOOR_H + 1), new THREE.MeshBasicMaterial({ color: 0x1c2a44 }));
      night.position.set(0, DOOR_H / 2 + 1, -A - 5); night.scale.set(2.6, 1.6, 1); this.walls.add(night);
      const yard = new THREE.Mesh(new THREE.PlaneGeometry(9, 5), new THREE.MeshStandardMaterial({ color: 0xdfe8f2, roughness: 1 }));
      yard.rotation.x = -Math.PI / 2; yard.position.set(0, 0.005, -A - 2.5); this.walls.add(yard);   // snowy ground outside
      this.outsideAt = new THREE.Vector3(0.6, 0, -A - 2.3);   // where the snowman stands (walls' local space)
      const coldLight = new THREE.PointLight(0x9cc4ff, 0.9, 12, 2); coldLight.position.set(0, DOOR_H * 0.6, -A + 1.2); this.walls.add(coldLight);
      const fade = canvasTex(256, 256, (g) => {
        const gr = g.createRadialGradient(128, 40, 10, 128, 60, 190);
        gr.addColorStop(0, '#fff'); gr.addColorStop(0.45, '#bbb'); gr.addColorStop(1, '#000');
        g.fillStyle = gr; g.fillRect(0, 0, 256, 256);
      });
      // the snowy planks line up board-for-board with the floor's planks (same tile size and offset)
      const FT = 3.2, DW = 8, DD = 7, DZ = -A + 3.4;
      const snowTex = tex('6or_garrison_woodfloor_snow', DW / FT, DD / FT);
      snowTex.offset.set(((-DW / 2 + RC) / FT) % 1, ((-(DZ + DD / 2) + RC) / FT) % 1);
      const drift = new THREE.Mesh(new THREE.PlaneGeometry(DW, DD), new THREE.MeshStandardMaterial({ map: snowTex, alphaMap: fade, transparent: true, depthWrite: false, roughness: 0.85 }));
      drift.rotation.x = -Math.PI / 2; drift.position.set(0, 0.01, DZ); drift.renderOrder = 1; this.walls.add(drift);
      const sn = 300, sp = new Float32Array(sn * 3);
      for(let i = 0; i < sn; i++){ sp[i * 3] = (Math.random() - 0.5) * (DOOR_W + 3); sp[i * 3 + 1] = Math.random() * DOOR_H; sp[i * 3 + 2] = -A - 4.5 + Math.random() * 5.5; }
      const sg = new THREE.BufferGeometry(); sg.setAttribute('position', new THREE.BufferAttribute(sp, 3));
      this.snowfall = new THREE.Points(sg, new THREE.PointsMaterial({ color: 0xffffff, size: 0.07, transparent: true, opacity: 0.85, depthWrite: false }));
      this.walls.add(this.snowfall); this.snowDoor = { w: DOOR_W + 2, h: DOOR_H, z0: -A - 1 };
      // the table: thick top, raised rim, four legs
      const pt = new THREE.Group(); S.add(pt); this.procTable = pt;   // stand-in until the real table loads
      const wt = woodTex('#5a3a1f', '30,16,6');
      const wood = new THREE.MeshStandardMaterial({ map: wt, roughness: 0.75 });
      const top = new THREE.Mesh(new THREE.BoxGeometry(11.6, 0.35, 7.6), wood); top.position.y = -0.2; top.receiveShadow = top.castShadow = true; pt.add(top);
      const rimMat = new THREE.MeshStandardMaterial({ map: wt, color: 0x9a7a52, roughness: 0.6 });
      [[0, -3.65, 11.6, 0.3], [0, 3.65, 11.6, 0.3], [-5.65, 0, 0.3, 7.6], [5.65, 0, 0.3, 7.6]].forEach(([x, z, w, d]) => {
        const r = new THREE.Mesh(new THREE.BoxGeometry(w, 0.22, d), rimMat); r.position.set(x, 0.06, z); r.castShadow = r.receiveShadow = true; pt.add(r);
      });
      [[-5, -3.2], [5, -3.2], [-5, 3.2], [5, 3.2]].forEach(([x, z]) => {
        const l = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.36, 2.9, 10), wood); l.position.set(x, -1.75, z); l.castShadow = true; pt.add(l);
      });
      // candles on the corners (the snow torches by the door load with the other models)
      this.flames = [];
      const candle = (x, y, z, s) => {
        const c = new THREE.Mesh(new THREE.CylinderGeometry(0.07 * s, 0.08 * s, 0.4 * s, 10), new THREE.MeshStandardMaterial({ color: 0xe8dcc0, roughness: 0.6 }));
        c.position.set(x, y + 0.2 * s, z); c.castShadow = true; S.add(c); (this.drawnCandles = this.drawnCandles || []).push(c);
        const f = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glow, color: 0xffb04a, blending: THREE.AdditiveBlending, depthWrite: false }));
        f.position.set(x, y + 0.48 * s, z); f.scale.set(0.22 * s, 0.4 * s, 1); S.add(f);
        const l = new THREE.PointLight(0xff9a3c, 0.5, 5 * s, 2); l.position.set(x, y + 0.6 * s, z); S.add(l);
        this.flames.push({ f, l, s, seed: Math.random() * 100, base: 0.5 }); (this.candleFx = this.candleFx || []).push({ x, z, f, l });
      };
      // two candles each side of the map, scattered a little differently every visit (clear of Leeroy's plate on the right)
      const spots = [];
      [-1, 1].forEach(side => {
        let tries = 0; const mine = [];
        while(mine.length < 2 && tries++ < 200){
          const z = (Math.random() * 2 - 1) * 3.9, x = side * (5.2 + Math.random() * 0.7);
          if(mine.some(m => Math.abs(m[1] - z) < 2.4)) continue;
          if(side > 0 && Math.abs(z - 0.6) < 1.3) continue;
          mine.push([x, z]);
        }
        spots.push(...mine);
      });
      this.candleSpots = spots;
      spots.forEach(([x, z]) => candle(x, 0.17, z, 1));
      // floating dust in the light
      const n = 260, pos = new Float32Array(n * 3);
      for(let i = 0; i < n; i++){ pos[i * 3] = (Math.random() - 0.5) * 14; pos[i * 3 + 1] = Math.random() * 8; pos[i * 3 + 2] = (Math.random() - 0.5) * 10; }
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      this.dust = new THREE.Points(g, new THREE.PointsMaterial({ map: this.glow, color: 0xffd9a0, size: 0.06, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false }));
      // (dust motes removed: they read as white dots over the map)
    }

    // ----- the real war table (Blackrook war table from the game) -----
    // Scaled so its top fits the map, then dropped so the tabletop sits at y = 0 under the map.
    loadTable(){
      if(!THREE.GLTFLoader) return;
      const T = window.WAR_TABLE || { url: 'models/war/wartable.gltf', width: 15.5 };
      new THREE.GLTFLoader().load(T.url, gltf => {
        const m = gltf.scene;
        // a static prop exported with one bone: swap the skinned meshes for plain ones so they sit in
        // their bind pose and raycasts (used to find the tabletop) see where they really are
        const skinned = []; m.traverse(o => { if(o.isSkinnedMesh) skinned.push(o); });
        skinned.forEach(o => { const p = new THREE.Mesh(o.geometry, o.material); p.name = o.name; p.position.copy(o.position); p.quaternion.copy(o.quaternion); p.scale.copy(o.scale); o.parent.add(p); o.parent.remove(o); });
        m.traverse(o => { if(o.isMesh){ o.castShadow = o.receiveShadow = true; o.material.side = THREE.DoubleSide; if(o.material && o.material.map) o.material.map.anisotropy = 8; } });
        const box = new THREE.Box3().setFromObject(m), size = box.getSize(new THREE.Vector3());
        const s = T.width / Math.max(size.x, size.z);
        m.scale.setScalar(s);
        m.position.set(-(box.min.x + box.max.x) / 2 * s, 0, -(box.min.z + box.max.z) / 2 * s);
        if(T.rotY) m.rotation.y = T.rotY;
        this.scene.add(m); m.updateMatrixWorld(true);
        // the tabletop is exported facing down, so draw both sides (this also lets rays hit it)
        // then sit the map just above the tabletop's centre; the carved rim stands proud of it
        const rc = new THREE.Raycaster();
        // Geoset3 is the round tabletop (the one with the painted map): its normals point down, so
        // flip them up or it renders nearly black. Measure the table height on it, not on the pins.
        // Geoset0 is a dark square card (an in-game blend layer) that would cover the whole top: hide it
        m.traverse(o => { if(o.isMesh && /Geoset0$/.test(o.name)) o.visible = false; });
        let topMesh = null;
        m.traverse(o => { if(o.isMesh && /Geoset3$/.test(o.name)) topMesh = o; });
        if(topMesh){
          // the geosets share one vertex list, so give the top its own copy before changing it
          const g = topMesh.geometry.clone(), n = g.attributes.normal.clone(), idx = g.index;
          for(let i = 0; i < idx.count; i++) n.setXYZ(idx.getX(i), 0, 1, 0);
          g.setAttribute('normal', n); topMesh.geometry = g;
          // its painted top is parchment too; darken it so the map's torn-out pieces read as holes
          topMesh.material = topMesh.material.clone(); topMesh.material.color.setHex(0x5a4532);
        }
        rc.set(new THREE.Vector3(0.5, 50, 0.5), new THREE.Vector3(0, -1, 0));
        const hit = rc.intersectObject(topMesh || m, true)[0];
        const top = hit ? hit.point.y : box.max.y * s;
        m.position.y = -top - 0.015 + (T.lift || 0);
        if(this.procTable){ this.scene.remove(this.procTable); this.procTable = null; }
        this.table = m; this.tableTop = top;
        // the floor goes under the real legs
        const fb = new THREE.Box3().setFromObject(m);
        if(this.floor) this.floor.position.y = fb.min.y;
        if(this.walls) this.walls.position.y = fb.min.y;
      }, undefined, err => console.warn('War table failed to load, keeping the stand-in:', err));
    }

    // ----- stronghold buildings (Horde garrison town hall / Alliance barracks) -----
    // Both are whole buildings with interiors, so: drop the interior rooms, merge what's left into one
    // mesh per material (a few draw calls instead of hundreds), and shrink it to a table piece.
    loadStrongholds(){
      if(!THREE.GLTFLoader) return;
      const S = window.WAR_STRONGHOLD_MODELS || {
        horde:    { url: 'models/war/horde-stronghold.gltf',    drop: /interior|foyer/i, mask: /hangingleather|clothroof/i, size: 0.5, rotY: Math.PI },
        horde_outpost: { url: 'models/war/horde-outpost.gltf', mask: /chain|clothfur|clothroof/i, size: 0.23, rotY: 0 },   // Warsong guard tower
        alliance_fortify: { url: 'models/war/fortify-alliance.gltf', size: 0.62, rotY: -1.309 },   // its gate (model +x, 15deg) turned to face the front   // Netherguard wall, a square enclosure round the zone's pieces
        alliance_outpost: { url: 'models/war/alliance-outpost.gltf', size: 0.21, rotY: 0 },   // Caverns of Time mage tower
        alliance: { sink: 0.14, url: 'models/war/alliance-stronghold.gltf', drop: /cellar|war_room|armordealer|weapondealer|generalarea/i, mask: /windows_01/i, size: 0.5, rotY: -Math.PI / 2 }
      };
      this.holdModels = {};
      Object.keys(S).forEach(f => {
        const cfg = S[f];
        new THREE.GLTFLoader().load(cfg.url, gltf => {
          gltf.scene.updateMatrixWorld(true);
          const byMat = new Map();
          gltf.scene.traverse(o => {
            if(!o.isMesh || (cfg.drop && cfg.drop.test(o.name))) return;
            const mats = Array.isArray(o.material) ? o.material : [o.material];
            const g = o.geometry.clone().applyMatrix4(o.matrixWorld);
            ['color', 'uv2', 'skinIndex', 'skinWeight', 'tangent'].forEach(a => g.deleteAttribute(a));
            if(!g.attributes.normal) g.computeVertexNormals();
            if(!g.attributes.uv) return;
            const ng = g.index ? g.toNonIndexed() : g;
            const key = mats[0].uuid;
            if(!byMat.has(key)) byMat.set(key, { mat: mats[0], geos: [] });
            byMat.get(key).geos.push(ng);
          });
          const grp = new THREE.Group();
          byMat.forEach(({ mat, geos }) => {
            const merged = THREE.BufferGeometryUtils ? THREE.BufferGeometryUtils.mergeBufferGeometries(geos) : null;
            mat.side = THREE.DoubleSide;
            // most WoW textures keep shininess in alpha, so only real cut-outs (window grilles, hanging cloth) get masked
            mat.transparent = false; mat.alphaTest = cfg.mask && cfg.mask.test(mat.name) ? 0.5 : 0;
            if(mat.map) mat.map.anisotropy = 4;
            (merged ? [merged] : geos).forEach(g => { const m = new THREE.Mesh(g, mat); m.castShadow = true; m.receiveShadow = true; grp.add(m); });
          });
          // shrink to a table piece, bottom-centred
          const box = new THREE.Box3().setFromObject(grp), size = box.getSize(new THREE.Vector3());
          const s = cfg.size / Math.max(size.x, size.z);
          const holder = new THREE.Group(), inner = new THREE.Group();
          grp.position.set(-(box.min.x + box.max.x) / 2, -box.min.y - (cfg.sink || 0) * (box.max.y - box.min.y), -(box.min.z + box.max.z) / 2);
          inner.add(grp); inner.scale.setScalar(s); inner.rotation.y = cfg.rotY || 0; holder.add(inner);
          this.holdModels[f] = holder;
          KEYS.forEach(k => this.syncPiece(k));
        }, undefined, err => console.warn(f + ' stronghold model failed to load, keeping the tower:', err));
      });
    }

    // ----- mountain + Blackrock Mountain models, normalised to 1 unit tall, bottom-centred -----
    loadTerrainModels(){
      if(!THREE.GLTFLoader) return;
      const M = window.WAR_TERRAIN_MODELS || TERRAIN_MODELS;
      this.terrainProtos = {}; let left = Object.keys(M).length;
      Object.keys(M).forEach(name => new THREE.GLTFLoader().load(M[name].url, gltf => {
        const m = gltf.scene, cfg = M[name];
        // rigged-but-static exports: swap skinned meshes for plain ones so copies render in their bind pose
        const skinned = []; m.traverse(o => { if(o.isSkinnedMesh) skinned.push(o); });
        skinned.forEach(o => { const q = new THREE.Mesh(o.geometry, o.material); q.name = o.name; q.position.copy(o.position); q.quaternion.copy(o.quaternion); q.scale.copy(o.scale); o.parent.add(q); o.parent.remove(o); });
        m.traverse(o => { if(o.isMesh){
          o.castShadow = o.receiveShadow = true; o.material.transparent = false; o.material.alphaTest = 0;
          if(cfg.tint) o.material.color = new THREE.Color(cfg.tint);
          if(cfg.glow && cfg.glow.test(o.material.name)){ o.material.emissive = new THREE.Color(0xff6a20); o.material.emissiveMap = o.material.map; o.material.emissiveIntensity = 1.2; }
        } });
        const box = new THREE.Box3().setFromObject(m), size = box.getSize(new THREE.Vector3());
        m.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
        const inner = new THREE.Group(); inner.add(m); inner.scale.setScalar(1 / size.y);
        const proto = new THREE.Group(); proto.add(inner);
        this.terrainProtos[name] = proto;
        if(name === 'mountain') this.terrainProtos.mountainSnow = this.snowCopy(proto, size.y, box.min.y);
        if(--left === 0 && this.raster) this.buildTerrain();
      }, undefined, err => { console.warn(name + ' terrain model failed to load:', err); if(--left === 0 && this.raster) this.buildTerrain(); }));
    }
    // the same mountain with white snow blended onto its upper slopes
    snowCopy(proto, height, minY){
      const c = proto.clone(true);
      c.traverse(o => { if(o.isMesh){
        const mat = o.material.clone();
        o.geometry.computeBoundingBox(); const gb = o.geometry.boundingBox;   // heights in the mesh's own units
        mat.onBeforeCompile = sh => {
          sh.uniforms.uSnowBase = { value: gb.min.y }; sh.uniforms.uSnowTop = { value: gb.max.y };
          sh.vertexShader = 'varying float vSnowH;\nuniform float uSnowBase;\nuniform float uSnowTop;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n  vSnowH = (position.y - uSnowBase) / (uSnowTop - uSnowBase);');
          sh.fragmentShader = 'varying float vSnowH;\n' + sh.fragmentShader.replace('#include <map_fragment>', '#include <map_fragment>\n  float snow = smoothstep(0.6, 0.78, vSnowH + (diffuseColor.r - 0.4) * 0.15);\n  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0), snow);');
        };
        mat.customProgramCacheKey = () => 'snowcap';
        o.material = mat;
      } });
      return c;
    }

    // ----- the Shadowfang door (swung open) and two Vrykul snow torches on the snowy wall either side -----
    loadDoorway(){
      if(!THREE.GLTFLoader || !this.outsideAt) return;
      const M = window.WAR_DOORWAY || { door: 'models/war/door.gltf', torch: 'models/war/snow-torch.gltf' };
      const A = -this.outsideAt.z - 2.3;   // the hall's apothem (the back wall's distance)
      new THREE.GLTFLoader().load(M.door, gltf => {
        const m = gltf.scene;
        m.traverse(o => { if(o.isMesh){ o.castShadow = o.receiveShadow = true; o.frustumCulled = false; o.material.side = THREE.DoubleSide; } });
        m.scale.set(-1.03, 1.03, 1.03); m.rotation.y = Math.PI / 2;   // width along the wall; mirrored so it swings into the hall, away from the snowman
        m.position.set(2.05, 0, -A + 0.05);                    // hinged on the right jamb
        this.walls.add(m);
        const mixer = new THREE.AnimationMixer(m), clip = n => gltf.animations.find(c => c.name === n);
        (this.mixers = this.mixers || []).push(mixer);
        let cur = mixer.clipAction(clip('Closed') || clip('Opened')); cur.play();
        this.doorOpen = !clip('Closed'); this.doorModel = m;
        // the rig moves the door when it opens but not its click area, so clicks go to two invisible
        // boxes instead: one filling the doorway (closed) and one where the open door stands
        const hitMat = new THREE.MeshBasicMaterial({ visible: false });
        const shut = new THREE.Mesh(new THREE.BoxGeometry(4.2, 5.3, 0.6), hitMat); shut.position.set(0, 2.65, -A);
        const swung = new THREE.Mesh(new THREE.BoxGeometry(0.7, 5.3, 4.3), hitMat); swung.position.set(2.0, 2.65, -A + 2.1);
        this.walls.add(shut, swung); this.doorHits = [shut, swung];
        this.frameDoor(m);
        // click the door: swing it shut / open (Close/Open play once, then it rests Closed/Opened)
        this.toggleDoor = () => {
          const swing = clip(this.doorOpen ? 'Close' : 'Open'), rest = clip(this.doorOpen ? 'Closed' : 'Opened');
          if(!swing) return;
          const a = mixer.clipAction(swing); a.reset(); a.setLoop(THREE.LoopOnce); a.clampWhenFinished = true;
          cur.stop(); a.play(); cur = a; this.doorOpen = !this.doorOpen;
          setTimeout(() => { if(cur === a && rest){ a.stop(); cur = mixer.clipAction(rest); cur.play(); } }, swing.duration * 1000);
        };
      }, undefined, err => console.warn('door failed to load:', err));
      new THREE.GLTFLoader().load(M.torch, gltf => {
        const proto = gltf.scene, box = new THREE.Box3().setFromObject(proto), s = 4.2 / (box.max.y - box.min.y);
        [-1, 1].forEach(side => {
          const t = THREE.SkeletonUtils ? THREE.SkeletonUtils.clone(proto) : proto.clone(true);
          t.traverse(o => { if(o.isMesh){
            o.frustumCulled = false; o.castShadow = true;
            // flame + glow cards burn additively; the iron plate is a cut-out
            if(/195953|189824/.test(o.material.name)){ if(/195953/.test(o.material.name)) o.name += '195953'; o.material = new THREE.MeshBasicMaterial({ map: o.material.map, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }); o.castShadow = false; this.torchFlames = (this.torchFlames || []).concat(o); }
            else { o.material = o.material.clone(); o.material.alphaTest = 0.4; o.material.transparent = false; o.material.side = THREE.DoubleSide; }
          } });
          // re-pivot the flame cards at their base so they can lick and sway from the bowl (the glow card just breathes)
          (this.torchFlames || []).filter(o => !o.userData.pivoted && t.getObjectById(o.id)).forEach(o => {
            o.geometry = o.geometry.clone(); o.geometry.computeBoundingBox(); const bb = o.geometry.boundingBox;
            const base = new THREE.Vector3((bb.min.x + bb.max.x) / 2, bb.min.y, (bb.min.z + bb.max.z) / 2);
            o.geometry.translate(-base.x, -base.y, -base.z); o.position.add(base);
            o.userData.pivoted = true; o.userData.flame = /195953/.test(o.name); o.userData.seed = Math.random() * 100;
            if(o.userData.flame){
              // a soft wave travelling up the flame: sideways bend that grows toward the tip (vertex shader)
              const H = Math.max(1e-4, bb.max.y - bb.min.y), u = { uTime: { value: 0 }, uH: { value: H }, uSeed: { value: o.userData.seed } };
              o.material = o.material.clone(); o.userData.waveU = u;
              o.material.onBeforeCompile = sh => {
                Object.assign(sh.uniforms, u);
                sh.vertexShader = 'uniform float uTime; uniform float uH; uniform float uSeed;\n' + sh.vertexShader.replace('#include <begin_vertex>', [
                  '#include <begin_vertex>',
                  'float h = clamp(position.y / uH, 0.0, 1.0);',
                  'float w = sin(position.y / uH * 4.0 - uTime * 3.2 + uSeed) * 0.6 + sin(position.y / uH * 7.0 - uTime * 4.7 + uSeed * 1.7) * 0.4;',
                  'transformed.x += w * h * h * uH * 0.07;',
                  'transformed.z += cos(position.y / uH * 3.0 - uTime * 2.6 + uSeed) * h * h * uH * 0.04;'].join('\n'));
              };
            }
          });
          t.scale.setScalar(s); t.position.set(side * 3.3, 1.2, -A + 0.9); t.rotation.y = -Math.PI / 2;   // bracket flat on the wall, flame up
          this.walls.add(t);
          // the light goes right in the flame
          t.updateMatrixWorld(true); const fb = new THREE.Box3();
          t.traverse(o => { if(o.isMesh && /195953/.test(o.name + (o.material.map && o.material.map.name || '')) ) fb.expandByObject(o); });
          const at = fb.isEmpty() ? new THREE.Vector3(side * 3.3, 4.6, -A + 1.6) : this.walls.worldToLocal(fb.getCenter(new THREE.Vector3()));
          const l = new THREE.PointLight(0xff9a40, 3.2, 20, 1.6); l.position.copy(at); l.position.z += 0.4; this.walls.add(l);
          this.flames.push({ f: { scale: { y: 0 } }, l, s: 1, seed: Math.random() * 100, base: 3.2 });
          if(gltf.animations[0]){ const mx = new THREE.AnimationMixer(t); mx.clipAction(gltf.animations[0]).play(); (this.mixers = this.mixers || []).push(mx); }
        });
      }, undefined, err => console.warn('snow torch failed to load:', err));
    }

    // ----- one vehicle per route: pirate ships on the goblin lines, Alliance transports on the ferries, zeppelins
    // on the zeppelin lines, all sailing their routes very slowly -----
    loadShips(){
      if(!THREE.GLTFLoader) return;
      const M = window.WAR_SHIPS || { pirate: 'models/war/pirate-ship.gltf', alliance: 'models/war/alliance-ship.gltf', zeppelin: 'models/war/zeppelin.gltf' };
      const protos = {};
      // one vehicle per route, sailing it end to end very slowly; at each end it eases round and heads back
      const KIND = r => r.kind === 'zeppelin' ? 'zeppelin' : (/barrens\|stranglethorn|tanaris\|riverglades/.test(r.a + '|' + r.b) ? 'pirate' : 'alliance');
      const place = () => {
        if(!this.raster) return setTimeout(place, 300);
        this.seaPaths = this.seaPaths || this.routeSeaPaths();
        (this.vehicles || []).forEach(v => this.scene.remove(v.obj)); this.vehicles = [];
        (this.routeLines || []).forEach((L, i) => {
          const kind = KIND(L.rt), proto = protos[kind]; if(!proto || L.pts.length < 2) return;
          const pts = L.pts.map(([x, y]) => { const w = toWorld(x, y); w.y = kind === 'zeppelin' ? 0.42 : this.sheetY(x, y) + 0.004; return w; });
          const cum = [0]; for(let j = 1; j < pts.length; j++) cum.push(cum[j - 1] + pts[j].distanceTo(pts[j - 1]));
          const obj = proto.clone(); this.scene.add(obj);
          // ~0.02 world units a second: a long crossing takes a few minutes
          this.vehicles.push({ obj, pts, cum, len: cum[cum.length - 1], kind, d: Math.random() * cum[cum.length - 1], dir: Math.random() < 0.5 ? 1 : -1, turn: 0, seed: i * 1.7, speed: kind === 'zeppelin' ? 0.011 : 0.008 });
        });
      };
      let left = Object.keys(M).length;
      Object.keys(M).forEach(kind => new THREE.GLTFLoader().load(M[kind], gltf => {
        gltf.scene.updateMatrixWorld(true);
        const byMat = new Map();
        gltf.scene.traverse(o => {
          if(!o.isMesh) return;
          const g = o.geometry.clone().applyMatrix4(o.matrixWorld);
          ['color', 'uv2', 'skinIndex', 'skinWeight', 'tangent'].forEach(a => g.deleteAttribute(a));
          if(!g.attributes.uv) return; if(!g.attributes.normal) g.computeVertexNormals();
          const ng = g.index ? g.toNonIndexed() : g, key = o.material.uuid;
          if(!byMat.has(key)) byMat.set(key, { mat: o.material, geos: [] }); byMat.get(key).geos.push(ng);
        });
        const grp = new THREE.Group();
        byMat.forEach(({ mat, geos }) => {
          const merged = THREE.BufferGeometryUtils ? THREE.BufferGeometryUtils.mergeBufferGeometries(geos) : null;
          mat.side = THREE.DoubleSide; mat.transparent = false; mat.alphaTest = 0;
          (merged ? [merged] : geos).forEach(g => { const m = new THREE.Mesh(g, mat); m.castShadow = true; grp.add(m); });
        });
        const box = new THREE.Box3().setFromObject(grp), s = (kind === 'zeppelin' ? 0.5 : 0.468) / (box.max.x - box.min.x);   // ships ~0.47 long, zeppelins 0.5
        grp.position.set(-(box.min.x + box.max.x) / 2, kind === 'zeppelin' ? -(box.min.y + box.max.y) / 2 : 0, -(box.min.z + box.max.z) / 2);      // ships: origin at the waterline; zeppelins: centred
        const holder = new THREE.Group(), inner = new THREE.Group(); inner.add(grp); inner.scale.setScalar(s); holder.add(inner);
        protos[kind] = holder;
        if(--left === 0) place();
      }, undefined, err => { console.warn(kind + ' ship failed to load:', err); if(--left === 0) place(); }));
    }

    // walk each vehicle along its route; the heading follows the path, and at an end it swings round
    moveVehicles(now, dt){
      (this.vehicles || []).forEach(v => {
        const at = d => { let j = 1; while(j < v.cum.length - 1 && v.cum[j] < d) j++; const a = v.pts[j - 1], c = v.pts[j], f = (d - v.cum[j - 1]) / ((v.cum[j] - v.cum[j - 1]) || 1); return [a.clone().lerp(c, Math.max(0, Math.min(1, f))), c.clone().sub(a)]; };
        if(v.turn > 0){ v.turn -= dt; if(v.turn <= 0) v.dir *= -1; }
        else { v.d += v.dir * v.speed * dt; if(v.d <= 0 || v.d >= v.len){ v.d = Math.max(0, Math.min(v.len, v.d)); v.turn = 4; v.from = v.obj.rotation.y; } }
        const [pos, tan] = at(v.d);
        let heading = Math.atan2(-tan.z * v.dir, tan.x * v.dir) + Math.PI;   // these models' bows point along -x
        if(v.turn > 0){ const k = 1 - v.turn / 4, target = heading + Math.PI; let diff = ((target - v.from) % (Math.PI * 2) + Math.PI * 3) % (Math.PI * 2) - Math.PI; heading = v.from + diff * (k * k * (3 - 2 * k)); }
        else { const cur = v.obj.rotation.y; let diff = ((heading - cur) % (Math.PI * 2) + Math.PI * 3) % (Math.PI * 2) - Math.PI; heading = cur + diff * Math.min(1, dt * 1.5); }
        v.obj.position.copy(pos); v.obj.rotation.y = heading;
        if(v.kind === 'zeppelin'){ v.obj.position.y = 0.42 + Math.sin(now / 1700 + v.seed) * 0.03; v.obj.rotation.z = Math.sin(now / 2300 + v.seed) * 0.025; }
        else { v.obj.rotation.z = Math.sin(now / 1400 + v.seed) * 0.04; v.obj.rotation.x = Math.sin(now / 1900 + v.seed) * 0.03; }
      });
    }

    // ----- paintings either side of the doorway: the Dalaran lady on the left, the Worgen portrait on the right -----
    loadPainting(){
      if(!THREE.GLTFLoader || !this.walls) return;
      // wall 7 is left of the doorway as seen from the table, wall 1 is right of it
      const list = window.WAR_PAINTINGS || [{ url: 'models/war/painting.gltf', wall: 7 }, { url: 'models/war/painting-worgen.gltf', wall: 1, flip: true }];   // flip: its picture faces -x
      list.forEach(pt => new THREE.GLTFLoader().load(pt.url, gltf => {
        const m = gltf.scene;
        const skinned = []; m.traverse(o => { if(o.isSkinnedMesh) skinned.push(o); });
        skinned.forEach(o => { const q = new THREE.Mesh(o.geometry, o.material); q.position.copy(o.position); q.quaternion.copy(o.quaternion); q.scale.copy(o.scale); o.parent.add(q); o.parent.remove(o); });
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.receiveShadow = true; } });
        const box = new THREE.Box3().setFromObject(m), s = 3.0 / (box.max.y - box.min.y);
        const A = 15, a = pt.wall * Math.PI / 4;
        const wall = new THREE.Group(); wall.position.set(A * Math.sin(a), 0, -A * Math.cos(a)); wall.rotation.y = -a;
        m.position.set(0, -(box.min.y + box.max.y) / 2, 0); m.position.x = pt.flip ? -box.max.x : -box.min.x;   // centred, back against the wall
        const hang = new THREE.Group(); hang.add(m); hang.scale.setScalar(s); hang.rotation.y = pt.flip ? Math.PI / 2 : -Math.PI / 2;   // its face toward the room
        hang.position.set(0, 5.0, 0.02); wall.add(hang); this.walls.add(wall);   // just above the table's sightline, so the camera's lowest tilt shows them
        const lamp = new THREE.SpotLight(0xffd9a0, 1.2, 9, 0.5, 0.6, 1.5);   // a little picture light
        lamp.position.set(0, 8.0, 1.6); lamp.target = hang; wall.add(lamp);
      }, undefined, err => console.warn('painting failed to load:', err)));
    }

    // ----- a succubus by the front wall, behind where the camera starts. She loops: stand, the Entice
    // emote, then turns her back and plays Drown -> Drowned, turns round again, and starts over.
    loadSuccubus(){
      if(!THREE.GLTFLoader || !this.walls) return;
      const url = window.WAR_SUCCUBUS || 'models/war/succubus.gltf';
      new THREE.GLTFLoader().load(url, gltf => {
        const m = gltf.scene, box = new THREE.Box3().setFromObject(m), s = 3.4 / (box.max.y - box.min.y);
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; o.material.alphaTest = 0.4; o.material.transparent = false; o.material.side = THREE.DoubleSide; } });
        const A = 15, FACE = Math.PI / 2;   // WoW models face +x; +PI/2 turns her toward the table (-z)
        m.scale.setScalar(s); m.position.set(0, -box.min.y * s, A - 2.2); m.rotation.y = FACE;
        this.walls.add(m);
        const glow = new THREE.PointLight(0xc060ff, 1.4, 7, 2); glow.position.set(0, 3.2, A - 0.8); this.walls.add(glow);   // a soft fel glow so she reads in the dim end of the hall
        const mixer = new THREE.AnimationMixer(m), clip = n => gltf.animations.find(c => c.name === n);
        (this.mixers = this.mixers || []).push(mixer);
        let cur = null;
        const play = (name, once) => {
          const c = clip(name); if(!c) return 0;
          const a = mixer.clipAction(c); a.reset(); a.setLoop(once ? THREE.LoopOnce : THREE.LoopRepeat); a.clampWhenFinished = !!once;
          if(cur && cur !== a) a.crossFadeFrom(cur, 0.3, false);
          a.play(); cur = a; return c.duration * 1000;
        };
        const turn = to => this.animate(700, t => { m.rotation.y = to.from + (to.to - to.from) * ease(t); });
        const wait = ms => new Promise(r => setTimeout(r, ms));
        const loop = async () => {
          for(;;){
            play('Stand'); await wait(5000);
            await wait(play('SuccubusEntice', true));
            play('Stand'); await turn({ from: FACE, to: FACE + Math.PI });
            await wait(play('Drown', true));
            play('Drowned'); await wait(4000);
            play('Stand'); await turn({ from: FACE + Math.PI, to: FACE + Math.PI * 2 }); m.rotation.y = FACE;
          }
        };
        loop();
      }, undefined, err => console.warn('succubus failed to load:', err));
    }

    // Replace the square frame with one cut to the door's outline: the convex hull of the door's
    // vertices (bind pose = closed) flattened onto the wall, as a hole in a planked panel round it.
    frameDoor(door){
      if(!this.doorWall) return;
      const W = this.doorWall; door.updateMatrixWorld(true); W.updateMatrixWorld(true);
      const pts = [], v = new THREE.Vector3();
      door.traverse(o => { if(!o.isMesh) return; const pa = o.geometry.attributes.position;
        for(let i = 0; i < pa.count; i += 2){ v.fromBufferAttribute(pa, i).applyMatrix4(o.matrixWorld); W.worldToLocal(v); pts.push([v.x, v.y]); } });
      if(pts.length < 3) return;
      pts.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
      const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
      const lo = [], hi = [];
      pts.forEach(p => { while(lo.length >= 2 && cross(lo[lo.length - 2], lo[lo.length - 1], p) <= 0) lo.pop(); lo.push(p); });
      for(let i = pts.length - 1; i >= 0; i--){ const p = pts[i]; while(hi.length >= 2 && cross(hi[hi.length - 2], hi[hi.length - 1], p) <= 0) hi.pop(); hi.push(p); }
      const hull = lo.slice(0, -1).concat(hi.slice(0, -1));
      const cx = hull.reduce((s, p) => s + p[0], 0) / hull.length;
      const minY = Math.min(...hull.map(p => p[1])), maxY = Math.max(...hull.map(p => p[1]));
      const minX = Math.min(...hull.map(p => p[0])), maxX = Math.max(...hull.map(p => p[0]));
      // a wooden frame that follows the door's outline (inner edge = the door, outer edge = 0.45 further out),
      // and snowy stone filling the rest of the square opening in the wall
      const M = 0.45, grow = (s, d) => hull.map(p => { const dx = p[0] - cx, dy = p[1] - (minY + maxY) / 2, L = Math.hypot(dx, dy) || 1; return [p[0] + dx / L * d, Math.max(minY, p[1] + dy / L * d)]; });
      const shapeOf = pts => { const s = new THREE.Shape(); pts.forEach((p, i) => i ? s.lineTo(p[0], p[1]) : s.moveTo(p[0], p[1])); s.closePath(); return s; };
      const pathOf = pts => { const s = new THREE.Path(); pts.slice().reverse().forEach((p, i) => i ? s.lineTo(p[0], p[1]) : s.moveTo(p[0], p[1])); s.closePath(); return s; };
      const inner = grow(0, 0.03), outerPts = grow(0, M);
      const ring = shapeOf(outerPts); ring.holes.push(pathOf(inner));
      const geo = new THREE.ExtrudeGeometry(ring, { depth: 0.45, bevelEnabled: true, bevelSize: 0.05, bevelThickness: 0.05, bevelSegments: 1 });
      const mat = this.doorFrameMat.clone(); mat.map = this.doorTex('127757', 0.3, 0.3);
      const frame = new THREE.Mesh(geo, mat); frame.position.z = -0.12; frame.castShadow = frame.receiveShadow = true;
      W.add(frame);
      const [DW, DH] = this.doorSize, fill = new THREE.Shape();
      fill.moveTo(-DW / 2 - 0.4, minY); fill.lineTo(DW / 2 + 0.4, minY); fill.lineTo(DW / 2 + 0.4, DH + 0.6); fill.lineTo(-DW / 2 - 0.4, DH + 0.6); fill.closePath();
      fill.holes.push(pathOf(outerPts));
      const stoneTex = this.doorStoneTex || null;
      const stone = new THREE.Mesh(new THREE.ExtrudeGeometry(fill, { depth: 0.2, bevelEnabled: false }), new THREE.MeshStandardMaterial({ map: stoneTex, color: stoneTex ? 0xffffff : 0x6a6660, roughness: 0.95 }));
      stone.position.z = -0.05; stone.receiveShadow = true; W.add(stone);
      frame.userData.fill = stone;
      (this.doorFrameParts || []).forEach(o => W.remove(o)); this.doorFrameParts = [frame, stone];
    }

    // ===== pets: every stationed pet stands beside its zone's banner, playing its idle =====
    syncPets(s){
      if(!THREE.GLTFLoader || !s || !s.players || this.smashed) return;
      // the troop plates show a paw where a pet guards: refresh the plates whose pet changed
      if(this.state){
        const zonesOf = st => new Set(Object.values(st.players || {}).filter(q => q.pet && q.petZone && !(q.petDown > st.clock)).map(q => q.petZone));
        const was = zonesOf(this.state), now = zonesOf(s);
        this.state.players = JSON.parse(JSON.stringify(s.players));
        new Set([...was, ...now]).forEach(k => { if(was.has(k) !== now.has(k) && this.pieces[k]) this.syncPiece(k); });
      }
      this.petModels = this.petModels || {}; this.petFiles = this.petFiles || {};
      const want = {};
      Object.values(s.players).forEach(p => {
        if(!p.pet || !p.petZone || !(s.zones[p.petZone] && s.zones[p.petZone].owner === p.faction) || p.petDown > s.clock) return;
        const stage = ['juvenile', 'adult', 'boss'].includes(p.pet.status) ? p.pet.status : 'juvenile';
        want[p.id] = { zone: p.petZone, url: `models/${p.pet.type}-${stage}.gltf?v=2`, type: p.pet.type, stage, built: (s.zones[p.petZone].outpost || 0) >= 1 };
      });
      // drop pets that fell, moved or changed model
      Object.keys(this.petModels).forEach(id => {
        const m = this.petModels[id], w = want[id];
        if(w && w.url === m.url && w.zone === m.zone && w.built === m.built) return;
        if(m.obj && m.obj.parent) m.obj.parent.remove(m.obj); if(m.mixer) this.mixers = this.mixers.filter(x => x !== m.mixer);
        delete this.petModels[id];
      });
      Object.keys(want).forEach(id => {
        if(this.petModels[id]) return;
        const w = want[id], rec = this.petModels[id] = { url: w.url, zone: w.zone, built: w.built, stage: w.stage };
        this.petFiles[w.url] = this.petFiles[w.url] || this.loadGltf(w.url);
        this.petFiles[w.url].then(g => {
          if(this.petModels[id] !== rec) return;
          const m = THREE.SkeletonUtils ? THREE.SkeletonUtils.clone(g.scene) : g.scene.clone();
          // the boss gryphon's alpha is a shading mask (render opaque); fx materials glow additively
          const cutout = !(w.type === 'gryphon' && w.stage === 'boss'), additive = /fx_blue|eyeglow|^5905220$|^166232$|^125647$/i;   // gryphon/cat glows, phoenix wing glows + flame tail
          m.traverse(o => { if(!o.isMesh) return; o.castShadow = true; o.frustumCulled = false; o.material = o.material.clone(); o.material.side = THREE.DoubleSide;
            if(additive.test(o.material.name || '')){ o.material.blending = THREE.AdditiveBlending; o.material.transparent = true; o.material.depthWrite = false; }
            else { o.material.alphaTest = cutout ? 0.4 : 0; o.material.transparent = false; } });
          const box = new THREE.Box3().setFromObject(g.scene), size = box.getSize(new THREE.Vector3());
          // lives in the zone's piece group (already scaled to the zone), standing just in front of the outpost /
          // stronghold's entrance (buildings face the camera, +z), or beside the banner when there is no building
          // size by stage, measured by footprint (the larger of length and wingspan) so a long-winged gryphon and a
          // stocky dragon of the same stage take up about the same room: juveniles small, adults 2x, bosses 2x adults
          const piece = this.pieces[w.zone], s2 = (PET_SPAN[w.stage] || 0.3) / Math.max(size.x, size.z);
          const holder = new THREE.Group(); holder.add(m); m.scale.setScalar(s2);
          m.position.set(-(box.min.x + box.max.x) / 2 * s2, -box.min.y * s2, -(box.min.z + box.max.z) / 2 * s2);
          const spot = piece.petSpot && piece.petSpot[w.stage];   // worked out per zone in fitPieces: clear of the building, inside the zone
          if(spot) holder.position.set(spot[0], 0.002, spot[1]);
          else if(w.built) holder.position.set((piece.bx || -0.2) + 0.02, 0.002, (piece.bz || -0.06) + 0.26);
          else holder.position.set(0.16, 0.002, 0.1);
          holder.rotation.y = -Math.PI / 2 + 0.35;   // turned to the camera
          piece.grp.add(holder); rec.obj = holder;
          const idle = g.animations.find(c => c.name === 'Stand');
          if(idle){ rec.mixer = new THREE.AnimationMixer(m); const act = rec.mixer.clipAction(idle); act.play(); act.time = Math.random() * idle.duration; (this.mixers = this.mixers || []).push(rec.mixer); }
          holder.scale.setScalar(0.01); this.animate(400, t => holder.scale.setScalar(Math.max(0.01, easeOut(t))));
        }).catch(err => console.warn('pet model failed to load:', w.url, err));
      });
    }

    // ===== the champion's smash: after the war, the winning side's MVP knocks the pieces off the table =====
    // Every visible piece on the map (banners, buildings, walls, pets) becomes loose debris with simple physics:
    // gravity, tumbling, bounces on the tabletop or the floor. A hit is { x, z, power, seed, t } (t = seconds into
    // the smash); the same hits give the same wreckage, so late visitors see what the champion did.
    smashBodies(){
      if(this.debris) return this.debris;
      this.smashed = true; this.debris = [];
      Object.values(this.pieces).forEach(p => {
        p.lab.style.display = 'none';
        p.grp.updateMatrixWorld(true);
        p.grp.children.slice().forEach(o => {
          if(!o.visible || o.geometry && o.geometry.type === 'RingGeometry') return;   // the owner ring stays painted on the map
          this.scene.attach(o);   // keep its world transform, now loose in the room
          const box = new THREE.Box3().setFromObject(o), size = box.getSize(new THREE.Vector3());
          if(!isFinite(size.y) || size.y <= 0) return;
          this.debris.push({ o, v: new THREE.Vector3(), w: new THREE.Vector3(), r: Math.max(0.03, Math.min(size.x, size.y, size.z) / 2), lift: o.position.y - box.min.y, rest: true });
        });
      });
      return this.debris;
    }
    // where a body stops falling: the tabletop over the table, the floor beyond its edge
    groundAt(x, z){ return Math.abs(x) < 7.4 && Math.abs(z) < 4.6 ? 0 : (this.floor ? this.floor.position.y : -3.1); }
    smashHit(h, live){
      const bodies = this.smashBodies(), rng = (() => { let s = h.seed >>> 0 || 1; return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296; })();
      const at = new THREE.Vector3(h.x, 0, h.z), R = 0.9 + h.power * 0.6;
      bodies.forEach(b => {
        const d = b.o.position.clone().setY(0).sub(at), dist = d.length(); if(dist > R) return;
        const f = Math.pow(1 - dist / R, 0.7) * h.power;
        d.y = 0; d.normalize(); if(!isFinite(d.x)) d.set(rng() - 0.5, 0, rng() - 0.5).normalize();
        b.v.add(new THREE.Vector3(d.x * (2.5 + rng() * 2), 3 + rng() * 3, d.z * (2.5 + rng() * 2)).multiplyScalar(f));
        b.w.add(new THREE.Vector3(rng() - 0.5, rng() - 0.5, rng() - 0.5).multiplyScalar(18 * f));
        b.rest = false;
      });
      if(live){
        this.shake(380, 0.08 + h.power * 0.08);
        this.sparks(at.clone().setY(0.05), 0xffd28a, 24, 0.9);
        this.flash(at, 0xffc070, 0.9);
      }
    }
    smashStep(dt){
      const g = -9.8;
      (this.debris || []).forEach(b => {
        if(b.rest) return;
        b.v.y += g * dt; b.o.position.addScaledVector(b.v, dt);
        b.o.rotation.x += b.w.x * dt; b.o.rotation.y += b.w.y * dt; b.o.rotation.z += b.w.z * dt;
        const floor = this.groundAt(b.o.position.x, b.o.position.z) + Math.min(b.lift, b.r);
        if(b.o.position.y < floor){
          b.o.position.y = floor;
          if(b.v.y < 0) b.v.y = -b.v.y * 0.32;
          b.v.x *= 0.7; b.v.z *= 0.7; b.w.multiplyScalar(0.6);
          if(b.v.length() < 0.15){ b.v.set(0, 0, 0); b.w.set(0, 0, 0); b.rest = true; }
        }
      });
    }
    // replay a list of hits with no animation (for anyone who opens the room after the smash)
    smashReplay(hits){
      if(!hits || !hits.length) return;
      this.smashBodies(); const dt = 1 / 60; let t = 0;
      hits.slice().sort((a, b) => a.t - b.t).forEach(h => {
        while(t < h.t){ this.smashStep(dt); t += dt; }
        this.smashHit(h, false);
      });
      for(let i = 0; i < 60 * 6; i++) this.smashStep(dt);   // let everything settle
    }
    // the swing itself: the side's legendary weapon (Gorehowl / the Ashbringer) chops down onto the spot from
    // over the champion's shoulder, its head landing where they clicked, then lifts and fades
    loadWeapons(){
      if(this.weaponsP) return this.weaponsP;
      const M = window.WAR_WEAPONS || { horde: 'models/war/weapon-gorehowl.gltf', alliance: 'models/war/weapon-ashbringer.gltf' };
      this.weapons = {};
      return this.weaponsP = Promise.all(Object.keys(M).map(f => this.loadGltf(M[f]).then(g => {
        const m = g.scene; m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; o.material.alphaTest = 0.4; o.material.transparent = false; o.material.side = THREE.DoubleSide; } });
        const box = new THREE.Box3().setFromObject(m), L = 1.7, s = L / (box.max.x - box.min.x);
        m.scale.setScalar(s); m.position.set(-box.min.x * s, -(box.min.y + box.max.y) / 2 * s, -(box.min.z + box.max.z) / 2 * s);   // handle end at the pivot, blade along +x
        const w = new THREE.Group(); w.add(m); this.weapons[f] = { proto: w, reach: L * 0.86 };
      }).catch(err => console.warn(f + ' weapon failed to load:', err))));
    }
    swingAt(clientX, clientY, faction, at){
      const W = this.weapons && this.weapons[faction];
      if(!W || !at){   // models not in yet: the emoji stands in
        const el = document.createElement('div'); el.className = 'wb-swing'; el.textContent = faction === 'alliance' ? '🔨' : '🪓';
        el.style.left = clientX + 'px'; el.style.top = clientY + 'px'; document.body.appendChild(el);
        setTimeout(() => el.remove(), 600); return;
      }
      const toCam = this.camera.position.clone().sub(at); toCam.y = 0; toCam.normalize();
      const pivot = at.clone().addScaledVector(toCam, W.reach); pivot.y = 0.12;
      const holder = new THREE.Group(); holder.position.copy(pivot);
      holder.rotation.y = Math.atan2(toCam.z, -toCam.x);   // local +x points from the pivot to the target
      holder.rotation.order = 'YZX';
      const wpn = W.proto.clone(); holder.add(wpn); this.scene.add(holder);
      // raised high, a quick wind-up, the chop, a small recoil, then away
      return this.animate(700, t => {
        let a;
        if(t < 0.25) a = 1.5 + Math.sin(t / 0.25 * Math.PI / 2) * 0.25;                 // wind up
        else if(t < 0.42) a = 1.75 * (1 - Math.pow((t - 0.25) / 0.17, 2));                // the chop (lands at t = 0.42)
        else if(t < 0.55) a = Math.sin((t - 0.42) / 0.13 * Math.PI) * 0.12;              // recoil
        else a = Math.pow((t - 0.55) / 0.45, 1.5) * 1.3;                                  // lift away
        holder.rotation.z = a;
        wpn.scale.setScalar(t > 0.8 ? Math.max(0.01, (1 - t) / 0.2) : 1);
      }).then(() => this.scene.remove(holder));
    }
    pointOnTable(clientX, clientY){
      const r = this.renderer.domElement.getBoundingClientRect();
      this.mouse.set(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
      this.raycaster.setFromCamera(this.mouse, this.camera);
      const p = new THREE.Vector3(); return this.raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), p) ? p : null;
    }

    // ===== easter eggs: Leeroy's chair, a rat on the table, Ragnaros in a lava pool, Onyxia's lair, the cow level =====
    egg(obj, fn){ (this.eggs = this.eggs || []).push({ obj, fn }); }
    eggSay(name, msg){ if(this.opts.onEgg) this.opts.onEgg(name, msg); }
    loadGltf(url){ return new Promise((res, rej) => new THREE.GLTFLoader().load(url, res, undefined, rej)); }
    prepModel(m){ m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; o.material.alphaTest = 0.4; o.material.transparent = false; o.material.side = THREE.DoubleSide; } }); return m; }
    playOnce(mixer, clips, name, then){
      const c = clips.find(c => c.name === name); if(!c) return 0;
      const a = mixer.clipAction(c); a.reset(); a.setLoop(THREE.LoopOnce); a.clampWhenFinished = true; a.play();
      const tc = then && clips.find(c => c.name === then);
      if(tc) setTimeout(() => { const b2 = mixer.clipAction(tc); b2.reset().play(); a.crossFadeTo(b2, 0.3, false); }, c.duration * 1000 - 300);
      return c.duration * 1000;
    }
    loadEggs(){
      if(!THREE.GLTFLoader || !this.walls) return;
      const M = window.WAR_EGGS || { chair: 'models/war/leeroy-chair.gltf', plate: 'models/war/food-plate.gltf', rat: 'models/war/rat.gltf', rag: 'models/war/ragnaros.gltf', tauren: 'models/war/tauren.gltf' };
      this.eggUrls = M;
      // --- Leeroy's chair: an empty rocking chair pulled back from the table, a plate of chicken on the seat
      const tableReady = new Promise(r => { const w = () => this.table ? r() : setTimeout(w, 200); w(); });
      Promise.all([this.loadGltf(M.chair), this.loadGltf(M.plate), tableReady]).then(([cg, pg]) => {
        const chair = this.prepModel(cg.scene), box = new THREE.Box3().setFromObject(chair), s = 3.3 / (box.max.y - box.min.y);
        const holder = new THREE.Group(); holder.add(chair); chair.scale.setScalar(s); chair.position.y = -box.min.y * s;
        holder.position.set(8.7, 0, 0.6); holder.rotation.y = Math.PI + 0.25;   // pulled up to the table's right side, facing it, a little askew
        this.walls.add(holder);
        // the plate sits on the tabletop's rim in front of the chair: find the top there with a ray
        const PLATE = this.platePos = new THREE.Vector3(6.5, 0.17, 0.6);   // at the table's edge right in front of the chair
        const rc = new THREE.Raycaster(); rc.set(new THREE.Vector3(PLATE.x, 50, PLATE.z), new THREE.Vector3(0, -1, 0));
        // walk in from the chair side until the ray finds tabletop (not the floor past its edge)
        for(let x = 6.5; x >= 5.4; x -= 0.15){ rc.set(new THREE.Vector3(x, 50, PLATE.z), new THREE.Vector3(0, -1, 0)); const th = rc.intersectObject(this.table, true)[0]; if(th && th.point.y > -0.4){ PLATE.x = x - 0.3; PLATE.y = th.point.y; break; } }
        const plate = this.prepModel(pg.scene), pb = new THREE.Box3().setFromObject(plate), ps = 0.9 / Math.max(pb.max.x - pb.min.x, pb.max.z - pb.min.z);
        plate.scale.setScalar(ps); plate.position.set(PLATE.x - (pb.min.x + pb.max.x) / 2 * ps, PLATE.y - pb.min.y * ps + 0.005, PLATE.z - (pb.min.z + pb.max.z) / 2 * ps); plate.rotation.y = 0.6;
        this.scene.add(plate); this.plate = plate;
        this.egg(plate, () => { const e = this.eggs.find(e => e.obj === holder); if(e) e.fn(); });
        let busy = false;
        this.egg(holder, () => {
          if(busy) return; busy = true; setTimeout(() => { busy = false; }, 2500);
          this.eggSay('leeroy', 'LEEEEROOOOY JENKINS!');
          // the chair rocks, and every piece on the board jumps
          this.animate(1600, t => { holder.rotation.z = Math.sin(t * Math.PI * 6) * 0.12 * (1 - t); });
          Object.values(this.pieces || {}).forEach(p => {
            const g = p.grp, y0 = g.position.y, d = Math.random() * 300;
            setTimeout(() => this.animate(520, t => { g.position.y = y0 + Math.sin(t * Math.PI) * 0.22; }).then(() => { g.position.y = y0; }), d);
          });
        });
      }).catch(err => console.warn('leeroy chair failed to load:', err));
      // --- a rat that now and then scurries along the table's edge between two candles
      this.loadGltf(M.rat).then(g => {
        this.ratProto = { scene: this.prepModel(g.scene), clips: g.animations };
        const box = new THREE.Box3().setFromObject(g.scene); this.ratScale = 0.6 / (box.max.x - box.min.x); this.ratLift = -box.min.y;
        // the first one 10-25 s after you come in, then one every 45-90 s
        const next = first => setTimeout(() => { this.spawnRat(); next(); }, first ? 10000 + Math.random() * 15000 : 45000 + Math.random() * 45000);
        next(true);
        window.spawnRat = () => { this.spawnRat(); return this.ratLive ? 'a rat is out' : 'no rat (one is already running?)'; };   // testing: summon one now
      }).catch(err => console.warn('rat failed to load:', err));
      // --- Ragnaros, half sunk in a little pool of lava on the floor by the table
      Promise.all([this.loadGltf(M.rag), this.loadGltf(M.lava || 'models/war/lava-pool.gltf').catch(() => null)]).then(([g, lp]) => this.placeRagnaros(g, lp)).catch(err => console.warn('ragnaros failed to load:', err));
      // --- Onyxia's lair: a smoking cave mouth in Dustwallow Marsh
      this.buildLair();
    }
    spawnRat(){
      if(!this.ratProto || this.ratLive) return;
      const R = this.ratProto, rat = THREE.SkeletonUtils ? THREE.SkeletonUtils.clone(R.scene) : R.scene.clone();
      const TINTS = [0xffffff, 0x9a8a78, 0x6b5440, 0x4a4440, 0xd8c8b0, 0x8a6a50];   // a random coat each time
      const tint = TINTS[Math.floor(Math.random() * TINTS.length)];
      rat.traverse(o => { if(o.isMesh){ o.material = o.material.clone(); o.material.color.setHex(tint); } });
      const s = this.ratScale; rat.scale.setScalar(s);
      const holder = new THREE.Group(); holder.add(rat); rat.position.y = this.ratLift * s; this.scene.add(holder);
      // an invisible, generous hit box: clicks test an animated model's rest pose, not the running rat you see
      const hitBox = new THREE.Mesh(new THREE.BoxGeometry(0.85, 0.45, 0.5), new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, colorWrite: false }));
      hitBox.position.y = 0.18; holder.add(hitBox);
      // from one candle corner to a neighbouring one, keeping clear of the candles themselves
      const C = (this.candleSpots || [[-5.55, -3.55], [5.55, -3.55], [5.55, 3.55], [-5.55, 3.55]]).slice().sort((p, q) => Math.atan2(p[1], p[0]) - Math.atan2(q[1], q[0])), i = Math.floor(Math.random() * C.length), j = (i + (Math.random() < 0.5 ? 1 : C.length - 1)) % C.length;
      const a = new THREE.Vector3(C[i][0], 0.17, C[i][1]), bb = new THREE.Vector3(C[j][0], 0.17, C[j][1]), dir = bb.clone().sub(a).normalize();
      a.addScaledVector(dir, 0.5); bb.addScaledVector(dir, -0.5);
      holder.position.copy(a); holder.rotation.y = Math.atan2(-dir.z, dir.x);
      const mixer = new THREE.AnimationMixer(rat); (this.mixers = this.mixers || []).push(mixer);
      const run = R.clips.find(c => c.name === 'Run'); if(run) mixer.clipAction(run).play();
      const live = { dead: false }; this.ratLive = live;
      const done = () => { this.scene.remove(holder); this.mixers = this.mixers.filter(m => m !== mixer); this.eggs = this.eggs.filter(e => e.obj !== holder); this.ratLive = null; };
      this.egg(holder, () => {
        if(live.dead) return; live.dead = true;
        let n = 0; try{ n = (+localStorage.getItem('gw_rats') || 0) + 1; localStorage.setItem('gw_rats', n); }catch(e){}
        this.eggSay('rat', n > 1 ? `Squeak! You caught a rat. (${n} so far)` : 'Squeak! You caught a rat.');
        mixer.stopAllAction(); this.playOnce(mixer, R.clips, 'Death');
        setTimeout(() => this.animate(600, t => { holder.scale.setScalar(Math.max(0.01, 1 - t)); }).then(done), 1800);
      });
      const legs = [[a, bb]];
      if(this.platePos && Math.random() < 0.6){
        // run to the plate, stop for a nibble, then off to the candle on the other side of it
        const P = this.platePos, R1 = new THREE.Vector3(5.55, P.y, -3.05), R2 = new THREE.Vector3(5.55, P.y, 3.05), from = Math.random() < 0.5 ? R1 : R2, to = from === R1 ? R2 : R1;
        const stopAt = new THREE.Vector3(Math.min(P.x - 0.45, 5.9), P.y, P.z + (from === R1 ? -0.45 : 0.45));
        legs.length = 0; legs.push([from, stopAt, true], [stopAt, to]);
        holder.position.copy(from);
      }
      const runLeg = i => {
        if(live.dead) return;
        if(i >= legs.length){ live.dead = true; done(); return; }
        const [p0, p1, stop] = legs[i], d = p1.clone().sub(p0);
        holder.rotation.y = Math.atan2(-d.z, d.x);
        this.animate(p0.distanceTo(p1) / 2.2 * 1000, t => { if(!live.dead) holder.position.lerpVectors(p0, p1, t); }).then(() => {
          if(live.dead) return;
          if(!stop){ runLeg(i + 1); return; }
          const standC = R.clips.find(c => c.name === 'Stand'), rn = run && mixer.clipAction(run), st = standC && mixer.clipAction(standC);
          if(rn && st){ st.reset().play(); rn.crossFadeTo(st, 0.2, false); }
          setTimeout(() => { if(live.dead) return; if(rn && st){ rn.reset().play(); st.crossFadeTo(rn, 0.2, false); } runLeg(i + 1); }, 2500 + Math.random() * 2500);
        });
      };
      runLeg(0);
    }
    placeRagnaros(g, lp){
      // under the front edge of the table, so he peeks out from beneath it
      const pool = new THREE.Group(); pool.position.set(0, 0, 3.2); this.walls.add(pool);
      if(lp){
        // WoW's volcanic lava pool: the lava and its crust are lit from within; the soft glow and flame sheets add light
        const m = lp.scene, box = new THREE.Box3();
        m.traverse(o => { if(!o.isMesh) return;
          const name = o.material.name || '', map = o.material.map;
          const fx = name === '3221835' || name === '3921706';
          o.material = new THREE.MeshBasicMaterial({ map, transparent: true, depthWrite: !fx, side: THREE.DoubleSide, blending: fx ? THREE.AdditiveBlending : THREE.NormalBlending, alphaTest: fx ? 0 : 0.05 });
          o.frustumCulled = false; o.renderOrder = fx ? 2 : 1;
          if(!fx){ o.geometry.computeBoundingBox(); box.union(o.geometry.boundingBox); } });
        const w = Math.max(box.max.x - box.min.x, box.max.z - box.min.z) || 30, s = 2.6 / w;
        m.scale.setScalar(s); m.position.y = 0.02; pool.add(m);
        if(lp.animations.length){ const mx = new THREE.AnimationMixer(m); mx.clipAction(lp.animations[0]).play(); (this.mixers = this.mixers || []).push(mx); }
      }
      const light = new THREE.PointLight(0xff6a1a, 1.8, 7, 2); light.position.y = 1.0; pool.add(light); this.lavaLight = light;
      let last = 0;
      this.lavaTick = now => { if(now - last < 60) return; last = now; if(!light.userData.roar) light.intensity = 1.6 + Math.sin(now / 170) * 0.25 + Math.random() * 0.25; };
      // Ragnaros, waist-deep (the floor hides his lower half). His texture's alpha is a glow mask, not cut-outs,
      // so his body renders solid and lit from within; the small flame geosets glow additively
      const m = g.scene, box = new THREE.Box3().setFromObject(m), s = 2.3 / (box.max.y - box.min.y);
      m.traverse(o => { if(!o.isMesh) return; o.castShadow = true; o.frustumCulled = false;
        const body = /Geoset[01]$/.test(o.name), mat = o.material.clone();
        if(body){ mat.alphaTest = 0; mat.transparent = false; mat.emissive = new THREE.Color(0xff7a30); mat.emissiveMap = mat.map; mat.emissiveIntensity = 0.55; }
        else { mat.transparent = true; mat.depthWrite = false; mat.blending = THREE.AdditiveBlending; mat.alphaTest = 0; }
        mat.side = THREE.DoubleSide; o.material = mat; });
      m.scale.setScalar(s); m.position.y = -box.min.y * s - 1.0; m.rotation.y = -Math.PI / 2;   // facing out into the room
      pool.add(m);
      const mixer = new THREE.AnimationMixer(m), clips = g.animations; (this.mixers = this.mixers || []).push(mixer);
      const st = clips.find(c => c.name === 'Stand'); if(st) mixer.clipAction(st).play();
      let busy = false;
      this.egg(pool, () => {
        if(busy) return; busy = true;
        this.eggSay('ragnaros', 'TOO SOON! YOU HAVE AWAKENED ME TOO SOON, EXECUTUS!');
        try{   // his voice line (R2: War Games/War Room/Ragnaros)
          const vo = new Audio('https://assets.hatedforever.com/War%20Games/War%20Room/Ragnaros/vo_fl_ragnaros_death_normal.ogg');
          vo.volume = 0.8; vo.play().catch(() => {});
        }catch(e){}
        const ms = this.playOnce(mixer, clips, 'EmoteRoar', 'Stand') || 2000;
        this.shake(900, 0.12); light.userData.roar = true;
        this.animate(ms, t => { light.intensity = 1.8 + Math.sin(t * Math.PI) * 4; }).then(() => { light.userData.roar = false; });
        setTimeout(() => { busy = false; }, ms + 500);
      });
    }
    buildLair(){
      // a dark cave mouth in Dustwallow's south-east with smoke curling out of it
      const at = toWorld(430, 912); at.y = this.sheetY(430, 912);
      const lair = new THREE.Group(); lair.position.copy(at); this.scene.add(lair);
      const rock = new THREE.Mesh(new THREE.SphereGeometry(0.11, 14, 10, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0x3a3028, roughness: 1 }));
      rock.scale.set(1.3, 0.8, 1); rock.castShadow = true; lair.add(rock);
      const mouth = new THREE.Mesh(new THREE.CircleGeometry(0.05, 16, 0, Math.PI), new THREE.MeshBasicMaterial({ color: 0x050302 }));
      mouth.position.set(0, 0.001, 0.105); mouth.scale.y = 1.2; lair.add(mouth);
      // Onyxia's cave (a WoW cave mouth), two copies back to back so it reads as a cave from every side of the table;
      // the little rock above stays only if the model can't load
      const CAVE = 'https://assets.hatedforever.com/War%20Games/Game%20Pieces/Onyxia%20Cave/8zul_cavemicro01.gltf';
      this.loadGltf(CAVE).then(g => {
        const box = new THREE.Box3().setFromObject(g.scene), size = box.getSize(new THREE.Vector3());
        const s = 0.075 / Math.max(size.x, size.z);   // small: a quarter of the old rock's footprint
        // its mouth opens toward +x: each copy's back sits on the lair's centre, mouths facing out both ways
        [0, Math.PI].forEach((ry, i) => {
          const m = i ? g.scene.clone(true) : g.scene; this.prepModel(m);
          const holder = new THREE.Group(); holder.rotation.y = ry; holder.add(m);
          m.scale.setScalar(s); m.position.set((-box.min.x - size.x * 0.35) * s, -box.min.y * s - 0.003, -(box.min.z + box.max.z) / 2 * s);   // backs overlap: the halves sit snug
          lair.add(holder);
        });
        lair.rotation.y = Math.PI / 2;   // mouths facing along the coast
        rock.visible = false; mouth.visible = false;
      }).catch(err => console.warn('Onyxia cave model failed to load:', err));
      const sc = document.createElement('canvas'); sc.width = sc.height = 64; const sx = sc.getContext('2d');
      const sg = sx.createRadialGradient(32, 32, 2, 32, 32, 30); sg.addColorStop(0, 'rgba(70,64,60,0.7)'); sg.addColorStop(1, 'rgba(70,64,60,0)'); sx.fillStyle = sg; sx.fillRect(0, 0, 64, 64);
      const smokeTex = new THREE.CanvasTexture(sc);
      this.lairSmoke = Array.from({ length: 7 }, (_, i) => { const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: smokeTex, transparent: true, depthWrite: false })); lair.add(sp); return { sp, ph: i / 7 }; });
      // whelps: the pet system's black whelp model (loaded on first use), a swarm of them bursting out when it's clicked
      const whelpGltf = () => this.whelpP || (this.whelpP = this.loadGltf('models/dragon-juvenile.gltf'));
      let busy = false;
      this.egg(lair, () => {
        if(busy) return; busy = true; setTimeout(() => { busy = false; }, 4000);
        this.eggSay('onyxia', 'MANY WHELPS! HANDLE IT!');
        try{ const vo = new Audio('https://assets.hatedforever.com/War%20Games/Game%20Pieces/Onyxia%20Cave/Many%20Welps.mp3'); vo.volume = 0.8; vo.play().catch(() => {}); }catch(e){}
        whelpGltf().then(g => {
          const box = new THREE.Box3().setFromObject(g.scene), ws = 0.07 / Math.max(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z);
          const fly = g.animations.find(c => c.name === 'Fly') || g.animations[0];
          for(let i = 0; i < 12; i++){
            const w = THREE.SkeletonUtils.clone(g.scene); w.traverse(o => { if(o.isMesh){ o.frustumCulled = false; o.material.alphaTest = 0.4; o.material.transparent = false; o.material.side = THREE.DoubleSide; } });
            const holder = new THREE.Group(); holder.add(w); w.scale.setScalar(ws); w.position.set(-(box.min.x + box.max.x) / 2 * ws, -(box.min.y + box.max.y) / 2 * ws, -(box.min.z + box.max.z) / 2 * ws);
            holder.scale.setScalar(0.01); lair.add(holder);
            const mx = new THREE.AnimationMixer(w); if(fly){ const act = mx.clipAction(fly); act.play(); act.time = Math.random() * fly.duration; act.timeScale = 1.4; } this.mixers.push(mx);
            const a0 = Math.random() * Math.PI * 2, r = 0.3 + Math.random() * 0.6, h = 0.5 + Math.random() * 0.8, spin = (Math.random() < 0.5 ? -1 : 1) * (2 + Math.random() * 2);
            let prev = null;
            setTimeout(() => this.animate(2800, t => {
              const a = a0 + t * spin, p = new THREE.Vector3(Math.cos(a) * r * t, 0.05 + h * t + Math.sin(t * 30) * 0.012, Math.sin(a) * r * t);
              if(prev){ const d = p.clone().sub(prev); holder.rotation.y = Math.atan2(-d.z, d.x); }   // WoW models face +x: fly where they're heading
              prev = p.clone(); holder.position.copy(p);
              holder.scale.setScalar(t < 0.1 ? Math.max(0.01, t / 0.1) : t > 0.85 ? Math.max(0.01, (1 - t) / 0.15) : 1);
            }).then(() => { lair.remove(holder); this.mixers = this.mixers.filter(m => m !== mx); }), i * 110);
          }
        }).catch(err => console.warn('whelp model failed to load:', err));
      });
    }
    tickEggs(now){
      // torch flames: a gentle, uneven flicker (stretch and a little sway); the glow breathes with it
      (this.torchFlames || []).forEach(o => {
        if(!o.userData.pivoted) return; const k = o.userData.seed, t = now / 1000;
        const n = Math.sin(t * 7.1 + k) * 0.5 + Math.sin(t * 11.3 + k * 2) * 0.3 + Math.sin(t * 17.9 + k * 3) * 0.2;   // -1..1, never regular
        if(o.userData.flame){ if(o.userData.waveU) o.userData.waveU.uTime.value = t; }
        else { const g = 1 + n * 0.04; o.scale.set(g, g, g); }
      });
      if(this.lavaTick) this.lavaTick(now);
      (this.domes || []).forEach(d => {   // shield domes shimmer; their sparkles drift up over the surface and twinkle
        d.material.opacity = 0.15 + Math.sin(now / 700) * 0.06;
        (d.userData.sparks || []).forEach(s => {
          const t = ((now / 3200) * s.sp0 + s.ph) % 1, el = Math.min(1.45, s.el + t * 0.9), a = s.a + t * 0.8, R = 0.245;
          s.sp.position.set(Math.cos(a) * Math.cos(el) * R, Math.sin(el) * R, Math.sin(a) * Math.cos(el) * R);
          const tw = Math.max(0, Math.sin(t * Math.PI)) * (0.6 + 0.4 * Math.sin(now / 90 + s.ph * 20));
          s.sp.material.opacity = tw; s.sp.scale.setScalar(0.035 + tw * 0.03); s.sp.material.rotation = now / 900 + s.ph * 6;
        });
      });
      (this.lairSmoke || []).forEach(o => { const t = ((now / 4200) + o.ph) % 1; o.sp.position.set(Math.sin(t * 6 + o.ph * 9) * 0.03, 0.06 + t * 0.35, 0.08); o.sp.scale.setScalar(0.06 + t * 0.16); o.sp.material.opacity = Math.sin(t * Math.PI) * 0.55; });
    }
    // the cow level: a tauren strolls across Mulgore, roars, and wanders off
    cowLevel(){
      if(this.cowBusy || !THREE.GLTFLoader) return; this.cowBusy = true;
      this.eggSay('cow', 'There is no cow level.');
      const go = g => {
        const m = this.prepModel(THREE.SkeletonUtils ? THREE.SkeletonUtils.clone(g.scene) : g.scene), box = new THREE.Box3().setFromObject(g.scene), s = 0.42 / (box.max.y - box.min.y);
        const holder = new THREE.Group(); holder.add(m); m.scale.setScalar(s); m.position.y = -box.min.y * s; this.scene.add(holder);
        const P = WAR_LAYOUT.mulgore, A = [P.x - 60, P.y + 30], B = [P.x + 55, P.y - 35];
        const pos = t => { const x = A[0] + (B[0] - A[0]) * t, y = A[1] + (B[1] - A[1]) * t, w = toWorld(x, y); w.y = this.sheetY(x, y); return w; };
        const d = pos(1).sub(pos(0)); holder.rotation.y = Math.atan2(-d.z, d.x); holder.position.copy(pos(0));
        const mixer = new THREE.AnimationMixer(m); (this.mixers = this.mixers || []).push(mixer);
        const clip = n => g.animations.find(c => c.name === n), walk = mixer.clipAction(clip('Walk')); walk.play();
        holder.scale.setScalar(0.01);
        this.animate(500, t => holder.scale.setScalar(Math.max(0.01, t)));
        this.animate(4200, t => holder.position.copy(pos(t * 0.5))).then(() => {
          walk.stop(); return sleep(this.playOnce(mixer, g.animations, 'EmoteRoar') || 1500);
        }).then(() => { mixer.stopAllAction(); mixer.clipAction(clip('Walk')).reset().play(); return this.animate(4200, t => holder.position.copy(pos(0.5 + t * 0.5))); })
          .then(() => this.animate(500, t => holder.scale.setScalar(Math.max(0.01, 1 - t))))
          .then(() => { this.scene.remove(holder); this.mixers = this.mixers.filter(x => x !== mixer); this.cowBusy = false; });
      };
      if(this.taurenGltf) go(this.taurenGltf);
      else this.loadGltf((this.eggUrls || {}).tauren || 'models/war/tauren.gltf').then(g => { this.taurenGltf = g; go(g); }).catch(err => { this.cowBusy = false; console.warn('tauren failed to load:', err); });
    }

    // ----- a snowman out in the snow beyond the doorway, under a little cloud of drifting snow -----
    loadSnowman(){
      if(!THREE.GLTFLoader || !this.outsideAt) return;
      const M = window.WAR_SNOWMAN || { man: 'models/war/snowman.gltf' };
      new THREE.GLTFLoader().load(M.man, gltf => {
        const m = gltf.scene, box = new THREE.Box3().setFromObject(m), s = 1.7 / (box.max.y - box.min.y);
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; o.material.alphaTest = 0.4; o.material.transparent = false; } });
        m.scale.setScalar(s); m.position.copy(this.outsideAt); m.position.y = -box.min.y * s; m.rotation.y = -0.35 - Math.PI / 2;   // turned to his right
        this.walls.add(m);
        const mixer = new THREE.AnimationMixer(m), clips = gltf.animations;
        const stand = clips.find(c => /Stand/.test(c.name)), wave = clips.find(c => /Wave/.test(c.name));
        if(stand) mixer.clipAction(stand).play();
        (this.mixers = this.mixers || []).push(mixer);
        // every so often he waves at the room
        if(wave && stand){
          const w = mixer.clipAction(wave); w.setLoop(THREE.LoopOnce); w.clampWhenFinished = false;
          setInterval(() => { w.reset().play(); mixer.clipAction(stand).crossFadeTo(w, 0.3); setTimeout(() => w.crossFadeTo(mixer.clipAction(stand).reset().play(), 0.4), wave.duration * 1000 - 400); }, 14000);
        }
      }, undefined, err => console.warn('snowman failed to load:', err));
    }

    // ----- scenery (World Tree on Teldrassil and Mount Hyjal) -----
    loadScenery(){
      if(!THREE.GLTFLoader) return;
      const M = window.WAR_SCENERY_MODELS || SCENERY_MODELS;
      Object.keys(M).forEach(name => new THREE.GLTFLoader().load(M[name].url, gltf => {
        const m = gltf.scene, cfg = M[name];
        m.traverse(o => { if(o.isMesh){ o.castShadow = o.receiveShadow = true; o.material.side = THREE.DoubleSide; o.material.transparent = false; o.material.alphaTest = cfg.mask && cfg.mask.test(o.material.name) ? 0.5 : 0; } });
        const box = new THREE.Box3().setFromObject(m), size = box.getSize(new THREE.Vector3());
        const s = cfg.height / size.y;
        m.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
        const proto = new THREE.Group(), inner = new THREE.Group(); inner.add(m); inner.scale.setScalar(s); proto.add(inner);
        Object.keys(SCENERY).filter(k => SCENERY[k].model === name).forEach((k, i) => {
          const p = WAR_LAYOUT[k], sc = SCENERY[k], x = p.x + sc.dx, y = p.y + sc.dy;
          const t = i ? proto.clone() : proto, at = toWorld(x, y);
          t.position.set(at.x, this.sheetY(x, y) - 0.01, at.z); t.rotation.y = i * 2.1;
          this.scene.add(t);
        });
      }, undefined, err => console.warn(name + ' scenery failed to load:', err)));
    }

    // ----- flags (WoW banner models with their idle wave): Horde, Alliance and a yellow neutral banner -----
    loadFlags(){
      if(!THREE.GLTFLoader || !THREE.SkeletonUtils) return;
      const F = window.WAR_FLAG_MODELS || {
        horde:    { url: 'models/war/horde-flag.gltf',    height: 0.46 },
        alliance: { url: 'models/war/alliance-flag.gltf', height: 0.46 },
        neutral:  { url: 'models/war/neutral-flag.gltf',  height: 0.42, cloth: 'z' }   // the yellow Brewfest banner
      };
      this.flagModels = {}; this.mixers = [];
      Object.keys(F).forEach(f => new THREE.GLTFLoader().load(F[f].url, gltf => {
        const m = gltf.scene;
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; o.material.side = THREE.DoubleSide; o.material.alphaTest = 0.4; o.material.transparent = false; } });
        const box = new THREE.Box3().setFromObject(m), size = box.getSize(new THREE.Vector3());
        const s = F[f].height / size.y;
        const inner = new THREE.Group(); inner.add(m);
        // stand the pole on the zone and turn the cloth to fly to the right (away from the stronghold)
        if(F[f].cloth === 'z'){ m.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -box.max.z); inner.rotation.y = -Math.PI / 2; }
        else { m.position.set(-box.max.x, -box.min.y, -(box.min.z + box.max.z) / 2); inner.rotation.y = Math.PI; }
        inner.scale.setScalar(s);
        this.flagModels[f] = { proto: inner, clip: gltf.animations[0] };
        KEYS.forEach(k => this.syncPiece(k));
      }, undefined, err => console.warn(f + ' flag failed to load, keeping the plain flag:', err)));
    }

    // ----- the map on the table -----
    buildMap(){
      const W = 2048, H = Math.round(2048 * MH / MW);
      const c = document.createElement('canvas'); c.width = W; c.height = H;
      this.mapCanvas = c; this.mapCtx = c.getContext('2d');
      // resource icons (the site's 2D icons)
      const R2 = 'https://assets.hatedforever.com/';
      this.resIcons = {};
      Object.entries({ food: 'FoodIcon.png', wood: 'WoodIcon.png', ore: 'War%20Games/CopperOre.png', gold: 'GoldIcon.png' }).forEach(([r, f]) => {
        const im = new Image(); im.crossOrigin = 'anonymous';
        im.onload = () => { this.resIcons[r] = im; this.drawMap(); };
        im.src = R2 + f + '?board=1';   // its own URL: the site's nav caches these icons without CORS, which blocks drawing them on the map
      });
      // the painted map and its zone outlines
      const base = new Image();
      base.onload = () => { this.baseImg = base; this.drawMap(); };
      base.src = WAR_MAP_IMAGE;
      const zim = new Image();
      zim.onload = () => {
        const zc = document.createElement('canvas'); zc.width = zim.width; zc.height = zim.height;
        const zg = zc.getContext('2d'); zg.drawImage(zim, 0, 0);
        const px = zg.getImageData(0, 0, zim.width, zim.height).data;
        this.RW = zim.width; this.RH = zim.height; this.raster = new Uint8Array(this.RW * this.RH);
        for(let i = 0; i < this.raster.length; i++) this.raster[i] = px[i * 4];
        this.overlayCanvas = document.createElement('canvas'); this.overlayCanvas.width = this.RW; this.overlayCanvas.height = this.RH;
        this.drawMap(); this.buildTerrain(); this.fitPieces();
      };
      zim.src = WAR_ZONE_IMAGE;
      this.mapTex = new THREE.CanvasTexture(c); this.mapTex.anisotropy = 8; this.mapTex.encoding = THREE.sRGBEncoding;
      // a finely divided sheet so the edges can curl
      const geo = new THREE.PlaneGeometry(PW, PH, 140, Math.round(140 * PH / PW));
      const pos = geo.attributes.position, uv = geo.attributes.uv;
      for(let i = 0; i < pos.count; i++) pos.setZ(i, curlHeight(uv.getX(i), uv.getY(i)));
      geo.computeVertexNormals();
      const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: this.mapTex, roughness: 0.92, alphaTest: 0.5 }));   // alpha: the torn edges
      m.add(new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: this.mapTex, color: 0x5a4a34, alphaTest: 0.5, roughness: 1, side: THREE.BackSide })));   // the parchment's back
      m.rotation.x = -Math.PI / 2; m.receiveShadow = true; m.castShadow = true;
      this.scene.add(m); this.mapMesh = m; this.mapGeo = geo;
      const wt = woodTex('#4a2f18', '24,12,4'); wt.wrapS = wt.wrapT = THREE.RepeatWrapping; wt.repeat.set(3, 3); wt.encoding = THREE.sRGBEncoding;
      const under = new THREE.Mesh(new THREE.PlaneGeometry(PW * 1.002, PH * 1.002), new THREE.MeshStandardMaterial({ map: wt, roughness: 0.8 }));
      under.rotation.x = -Math.PI / 2; under.position.y = -0.012; under.receiveShadow = true; this.underMap = under;   // not added: the torn holes show the real tabletop
      this.drawMap();
    }
    // Boat routes: shortest sea path (A* on a coarse grid of the outline map) from the coast nearest one
    // zone's anchor to the coast nearest the other's, kept a little off the shore, then thinned to waypoints.
    // harbours: where boat lines land for a zone (map px); others land on the coast nearest the zone's banner
    routeSeaPaths(){
      const HARBOURS = { wetlands: [918, 624], stranglethorn: [848, 1214], elwynn: [794, 906], hillsbrad: [897, 447] };   // + Southshore's dock on Hillsbrad's south coast   // + Stormwind Harbor on Elwynn's west coast   // Menethil Harbor (west coast); Booty Bay (southern tip) - boats only
      const ZEP_TOWERS = { stranglethorn: [866, 1108] };                        // Grom'gol, on Stranglethorn's west coast
      const S = 3, R = this.raster, RW = this.RW, RH = this.RH;
      const GW = Math.floor(RW / S), GH = Math.floor(RH / S), N = GW * GH;
      const sea = new Uint8Array(N);
      for(let gy = 0; gy < GH; gy++) for(let gx = 0; gx < GW; gx++){
        let water = true;
        for(let y = 0; y < S && water; y++) for(let x = 0; x < S; x++){ const v = R[(gy * S + y) * RW + gx * S + x]; if(v !== 0){ water = false; break; } }
        sea[gy * GW + gx] = water ? 1 : 0;
      }
      // distance to land (grid steps), so routes keep a little water between them and the coast
      const dist = new Float32Array(N).fill(1e9), q = [];
      for(let i = 0; i < N; i++) if(!sea[i]){ dist[i] = 0; q.push(i); }
      for(let h = 0; h < q.length; h++){
        const i = q[h], x = i % GW, y = (i / GW) | 0;
        [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([dx, dy]) => {
          const nx = x + dx, ny = y + dy; if(nx < 0 || ny < 0 || nx >= GW || ny >= GH) return;
          const j = ny * GW + nx; if(dist[j] > dist[i] + 1){ dist[j] = dist[i] + 1; q.push(j); }
        });
      }
      const lane = { boat: new Uint8Array(N), zeppelin: new Uint8Array(N) }; let laneOf = new Uint8Array(N), nearEnds = new Uint8Array(N);   // laneOf: every lane so far, both kinds, widened
      let lanePen = 40; const cost = i => (1 + 8 * Math.exp(-dist[i] / 2.5)) + (laneOf[i] && !nearEnds[i] ? lanePen : 0);
      const toG = (mx, my) => [Math.floor(mx / MW * RW / S), Math.floor(my / MH * RH / S)];
      const nearestSea = (mx, my, toward) => {
        const [cx, cy] = toG(mx, my); let best = -1, bd = 1e9;
        for(let r = 1; r < 60 && best < 0; r++) for(let y = cy - r; y <= cy + r; y++) for(let x = cx - r; x <= cx + r; x++){
          if(x < 0 || y < 0 || x >= GW || y >= GH) continue; const i = y * GW + x; if(!sea[i] || dist[i] < 2) continue;
          const d = Math.hypot(x - cx, y - cy) + 0.25 * Math.hypot(x - toward[0], y - toward[1]);
          if(d < bd){ bd = d; best = i; }
        }
        return best;
      };
      const astar = (s, t) => {
        const g = new Float32Array(N).fill(Infinity), from = new Int32Array(N).fill(-1), done = new Uint8Array(N); g[s] = 0;
        const tx = t % GW, ty = (t / GW) | 0, hz = i => Math.hypot(i % GW - tx, ((i / GW) | 0) - ty);
        // binary min-heap of [priority, cell]
        const heap = [[0, s]];
        const push = e => { heap.push(e); let k = heap.length - 1; while(k){ const p = (k - 1) >> 1; if(heap[p][0] <= heap[k][0]) break; [heap[p], heap[k]] = [heap[k], heap[p]]; k = p; } };
        const pop = () => { const top = heap[0], last = heap.pop(); if(heap.length){ heap[0] = last; let k = 0; for(;;){ const l = 2 * k + 1, r = l + 1; let m = k; if(l < heap.length && heap[l][0] < heap[m][0]) m = l; if(r < heap.length && heap[r][0] < heap[m][0]) m = r; if(m === k) break; [heap[m], heap[k]] = [heap[k], heap[m]]; k = m; } } return top; };
        while(heap.length){
          const [, i] = pop(); if(done[i]) continue; done[i] = 1;
          if(i === t) break;
          const x = i % GW, y = (i / GW) | 0;
          for(let dy = -1; dy <= 1; dy++) for(let dx = -1; dx <= 1; dx++){
            if(!dx && !dy) continue; const nx = x + dx, ny = y + dy; if(nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue;
            const j = ny * GW + nx; if(!sea[j] || (dist[j] < 3 && !nearEnds[j])) continue;   // open water only (no narrow inlets), except at its own ports
            const ng = g[i] + cost(j) * (dx && dy ? 1.414 : 1);
            if(ng < g[j]){ g[j] = ng; from[j] = i; push([ng + hz(j), j]); }
          }
        }
        if(from[t] < 0 && s !== t) return null;
        const out = []; for(let i = t; i >= 0; i = from[i]){ out.push(i); if(i === s) break; }
        return out.reverse();
      };
      const paths = {};
      // every route (boats and zeppelins) goes by sea; longest first, so shorter ones join their lanes
      const edges = { boat: new Set(), zeppelin: new Set() }; this.routeLines = [];
      const cellPt0 = c => [((c % GW) + 0.5) * S / RW * MW, (((c / GW) | 0) + 0.5) * S / RH * MH], cellPt = cellPt0;
      const routes = WAR_ROUTES.slice().sort((p, q) => {
        const d = r => Math.hypot(WAR_LAYOUT[r.a].x - WAR_LAYOUT[r.b].x, WAR_LAYOUT[r.a].y - WAR_LAYOUT[r.b].y);
        return d(q) - d(p);
      });
      routes.forEach(rt => {
        const kind = rt.kind === 'zeppelin' ? 'zeppelin' : 'boat';
        const A = WAR_LAYOUT[rt.a], B = WAR_LAYOUT[rt.b];
        const ports = kind === 'boat' ? HARBOURS : ZEP_TOWERS, ha = ports[rt.a], hb = ports[rt.b];
        const pa = ha || [A.x, A.y], pb = hb || [B.x, B.y];
        const s = nearestSea(pa[0], pa[1], ha ? toG(...pa) : toG(B.x, B.y)), t = nearestSea(pb[0], pb[1], hb ? toG(...pb) : toG(A.x, A.y));
        if(s < 0 || t < 0) return;
        // near this route's own ends, other lanes are allowed (ports are shared)
        nearEnds = new Uint8Array(N); [s, t].forEach(c0 => { const x0 = c0 % GW, y0 = (c0 / GW) | 0; for(let dy = -7; dy <= 7; dy++) for(let dx = -7; dx <= 7; dx++){ const x = x0 + dx, y = y0 + dy; if(x >= 0 && y >= 0 && x < GW && y < GH) nearEnds[y * GW + x] = 1; } });
        // avoid other lanes, but never at the price of a big detour: if dodging them makes the trip more than
        // ~12% longer than the direct sea path, dodge less, and in the end just cross them
        lanePen = 0; const direct = astar(s, t); if(!direct) return;
        let cells = null;
        for(const pen of [40, 8, 0]){ lanePen = pen; const c = pen ? astar(s, t) : direct; if(c && c.length <= direct.length * 1.12){ cells = c; break; } }
        cells = cells || direct;
        cells.forEach(c => { const x0 = c % GW, y0 = (c / GW) | 0; for(let dy = -2; dy <= 2; dy++) for(let dx = -2; dx <= 2; dx++){ const x = x0 + dx, y = y0 + dy; if(x >= 0 && y >= 0 && x < GW && y < GH) laneOf[y * GW + x] = 1; } });
        cells.forEach((c, i) => { if(i) edges[kind].add(Math.min(c, cells[i - 1]) + ',' + Math.max(c, cells[i - 1])); });
        const pts = cells.filter((_, i) => i % 6 === 0 || i === cells.length - 1)
          .map(i => [((i % GW) + 0.5) * S / RW * MW, ((((i / GW) | 0) + 0.5) * S) / RH * MH]);
        // run the line right into the harbour
        if(ha){ pts.unshift(ha); edges[kind].add('H' + rt.a + ',' + s); }
        if(hb){ pts.push(hb); edges[kind].add('H' + rt.b + ',' + t); }
        paths[rt.a + '|' + rt.b] = pts;
        const full = cells.filter((_, i) => i % 2 === 0 || i === cells.length - 1).map(c => cellPt(c));
        if(ha) full.unshift(ha); if(hb) full.push(hb);
        (this.routeLines = this.routeLines || []).push({ rt, kind, pts: full, cells: new Set(cells) });
      });
      // the network: each shared stretch drawn once. Chain the edges into polylines between junctions.
      const cellPtH = c => typeof c === 'string' ? (HARBOURS[c.slice(1)] || ZEP_TOWERS[c.slice(1)]) : cellPt0(c);
      this.routeNet = {};
      Object.keys(edges).forEach(kind => {
        const adj = new Map(), key = v => String(v);
        edges[kind].forEach(e => { const [a, bb] = e.split(',').map(v => v[0] === 'H' ? v : +v); [[a, bb], [bb, a]].forEach(([u, w]) => { if(!adj.has(key(u))) adj.set(key(u), { v: u, n: [] }); adj.get(key(u)).n.push(w); }); });
        const used = new Set(), lines = [], ek = (u, w) => [key(u), key(w)].sort().join('|');
        const walk = (start, next) => {
          const line = [start, next]; used.add(ek(start, next)); let prev = start, cur = next;
          while(adj.get(key(cur)).n.length === 2){
            const nx = adj.get(key(cur)).n.find(w => key(w) !== key(prev)); if(used.has(ek(cur, nx))) break;
            used.add(ek(cur, nx)); line.push(nx); prev = cur; cur = nx;
          }
          lines.push(line);
        };
        adj.forEach(({ v, n }) => { if(n.length !== 2) n.forEach(w => { if(!used.has(ek(v, w))) walk(v, w); }); });
        adj.forEach(({ v, n }) => n.forEach(w => { if(!used.has(ek(v, w))) walk(v, w); }));   // loops
        this.routeNet[kind] = lines.map(line => line.filter((_, i) => i % 4 === 0 || i === line.length - 1).map(cellPtH));
      });
      return paths;
    }

    // height of the curled sheet at a map point, so things placed near the edge sit on it
    sheetY(x, y){ return curlHeight(x / MW, 1 - y / MH); }
    ownerOf(k){ return this.state && this.state.zones[k] ? this.state.zones[k].owner : 'neutral'; }
    drawMap(){
      const g = this.mapCtx, W = this.mapCanvas.width, H = this.mapCanvas.height, sx = W / MW, sy = H / MH;
      g.fillStyle = '#7d7563'; g.fillRect(0, 0, W, H);
      if(this.baseImg) g.drawImage(this.baseImg, 0, 0, W, H);
      // owner tint + zone borders, drawn at the outline map's resolution and scaled up smoothly
      if(this.raster){
        const RW = this.RW, RH = this.RH, R = this.raster;
        const oc = this.overlayCanvas.getContext('2d'), im = oc.createImageData(RW, RH), d = im.data;
        // region rims (worked out once): how close each pixel is to the edge of its region; the hovered region glows
        const REG_KEYS = Object.keys(WAR_REGIONS), REG_COL = [null].concat(REG_KEYS.map(r => { const h = WAR_REGIONS[r].color || '#d6a940'; return [1, 3, 5].map(j => parseInt(h.slice(j, j + 2), 16)); }));
        if(!this.regionEdge){
          const regOf = new Uint8Array(256); WAR_ZONE_ORDER.forEach((k, i) => { regOf[i + 1] = REG_KEYS.indexOf(WAR_ZONES[k].region) + 1; });
          const E2 = new Uint8Array(RW * RH);
          for(let y = 0; y < RH; y++) for(let x = 0; x < RW; x++){
            const z = R[y * RW + x]; if(!isZone(z)) continue; const me = regOf[z]; this.regionOfPx = regOf;
            let best = 0;
            for(let dy = -4; dy <= 4; dy++) for(let dx = -4; dx <= 4; dx++){
              const xx = x + dx, yy = y + dy, dd = Math.max(Math.abs(dx), Math.abs(dy));
              const q = xx < 0 || yy < 0 || xx >= RW || yy >= RH ? 0 : R[yy * RW + xx];
              if(regOf[q] !== me && (!best || dd < best)) best = dd;
            }
            E2[y * RW + x] = best;
          }
          this.regionEdge = E2;
        }
        const hr = this.hoverRegion ? Object.keys(WAR_REGIONS).indexOf(this.hoverRegion) + 1 : 0;
        if(!this.boldPx){
          // Silverpine / Alterac meet along Lordamere Lake's shoreline art, where a thin line disappears: widen it
          const BOLD = [['silverpine', 'alterac']].map(([a, c]) => [this.zoneVal[a], this.zoneVal[c]]), bp = new Uint8Array(RW * RH);
          for(let y = 1; y < RH - 1; y++) for(let x = 1; x < RW - 1; x++){
            const i = y * RW + x, z = R[i];
            BOLD.forEach(([a, c]) => { if(z !== a && z !== c) return; const o2 = z === a ? c : a;
              if(R[i + 1] === o2 || R[i - 1] === o2 || R[i + RW] === o2 || R[i - RW] === o2) for(let dy = -1; dy <= 1; dy++) for(let dx = -1; dx <= 1; dx++) if(isZone(R[i + dy * RW + dx])) bp[i + dy * RW + dx] = 1; });
          }
          this.boldPx = bp;
        }
        const own = new Array(256).fill(null);
        WAR_ZONE_ORDER.forEach((k, i) => { own[i + 1] = this.ownerOf(k); });
        const sel = this.selected ? this.zoneVal[this.selected] : -1;
        const hl = new Set((this.highlights || []).map(k => this.zoneVal[k]));
        for(let y = 0; y < RH; y++) for(let x = 0; x < RW; x++){
          const i = y * RW + x, z = R[i], o = i * 4;
          if(!isZone(z)) continue;
          const r = x + 1 < RW ? R[i + 1] : z, b = y + 1 < RH ? R[i + RW] : z, l = x > 0 ? R[i - 1] : z, t = y > 0 ? R[i - RW] : z;
          let border = (isZone(r) && r !== z) || (isZone(b) && b !== z) || (isZone(l) && l !== z) || (isZone(t) && t !== z);
          if(!border && this.boldPx && this.boldPx[i]) border = true;   // borders drawn thicker where the painted shore hides them
          const hov = hr && this.regionOfPx[z] === hr;
          if(hov && this.regionEdge[i]){ const t = Math.min(1, this.regionEdge[i] / 4); d[o] = 255; d[o + 1] = 214; d[o + 2] = 120; d[o + 3] = Math.round(235 - t * 150); continue; }   // the region's rim, fading inward
          if(border){ d[o] = 40; d[o + 1] = 24; d[o + 2] = 10; d[o + 3] = 200; continue; }
          const c = COL[own[z]] || COL.neutral;
          let a = own[z] === 'neutral' ? 0 : 0.36, cr = c[0], cg = c[1], cb = c[2];
          if(hov){ cr = Math.round(cr * (1 - 0.4) + 255 * 0.4); cg = Math.round(cg * 0.6 + 220 * 0.4); cb = Math.round(cb * 0.6 + 140 * 0.4); a += 0.12; }   // hovered region: a faint warm glow
          if(z === sel){ cr = 255; cg = 225; cb = 150; a += 0.16; }
          else if(hl.has(z)){ cr = 255; cg = 190; cb = 120; a += 0.08; }
          d[o] = cr; d[o + 1] = cg; d[o + 2] = cb; d[o + 3] = Math.round(Math.min(1, a) * 255);
        }
        oc.putImageData(im, 0, 0);
        g.imageSmoothingEnabled = true;
        g.drawImage(this.overlayCanvas, 0, 0, W, H);
      }
      // routes: each in its own colour; where routes share water they run side by side, not on top of each other
      if(this.raster){ this.seaPaths = this.seaPaths || this.routeSeaPaths(); }
      const ROUTE_COLOURS = ['#1f5f8b', '#8b2f6b', '#2f7a3a', '#b0641a', '#5a3f9e', '#1b7f7a', '#9e2a2a', '#c9a227', '#f2ead8', '#7a4a1f'];   // all distinct from the sea (the ferry lanes had a navy that vanished into it)
      // with a zone selected, its routes light up (thicker, glowing, drawn on top) and the rest fade back
      const lines = this.routeLines || [], sel = this.selected, lit = L => sel && (L.rt.a === sel || L.rt.b === sel);
      lines.map((L, li) => [L, li]).sort((p, q) => lit(p[0]) - lit(q[0])).forEach(([L, li]) => {
        const pts = L.pts; if(pts.length < 2) return;
        const on = lit(L);
        // sideways offset per point: spread the routes that pass through the same water
        const off = pts.map(() => [0, 0]);
        const P = pts.map((p, i) => [(p[0] + off[i][0]) * sx, (p[1] + off[i][1]) * sy]);
        const path = () => { g.beginPath(); g.moveTo(P[0][0], P[0][1]);
          for(let i = 1; i < P.length - 1; i++) g.quadraticCurveTo(P[i][0], P[i][1], (P[i][0] + P[i + 1][0]) / 2, (P[i][1] + P[i + 1][1]) / 2);
          g.lineTo(P[P.length - 1][0], P[P.length - 1][1]); };
        g.lineCap = 'round';
        if(on){   // a warm glow under the lit route
          g.setLineDash([]); g.lineWidth = 16; g.strokeStyle = 'rgba(255,214,110,0.55)'; g.globalAlpha = 1;
          g.shadowColor = 'rgba(255,200,80,0.95)'; g.shadowBlur = 18; path(); g.stroke(); g.shadowBlur = 0;
        }
        g.setLineDash(L.kind === 'zeppelin' ? [8, 12] : [18, 11]); g.lineWidth = (L.kind === 'zeppelin' ? 3.5 : 4.5) * (on ? 1.6 : 1);
        g.strokeStyle = ROUTE_COLOURS[li % ROUTE_COLOURS.length]; g.globalAlpha = on ? 1 : sel ? 0.35 : 0.8;
        path(); g.stroke();
      });
      g.setLineDash([]); g.lineCap = 'butt'; g.globalAlpha = 1; g.shadowBlur = 0;
      // resource icons: every zone shows its type faintly; this game's rich deposits are bold with a gold ring
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], r = WAR_ZONES[k].resource, im = this.resIcons && this.resIcons[r];
        const rich = this.state && this.state.rich ? !!this.state.rich[k] : false;
        if(!rich) return;   // only this war's rich deposits show an icon
        const off = Math.min(46, p.r * 0.45);
        const ic = TUNE.icons[k] || [p.x + off, p.y - off * 0.2];
        const cx = ic[0] * sx, cy = ic[1] * sy, size = Math.min(rich ? 54 : 42, 14 + p.r * 0.9);
        g.save();
        if(rich){
          g.globalAlpha = 0.9; g.strokeStyle = '#d6a940'; g.lineWidth = 4; g.fillStyle = 'rgba(255,236,170,0.35)';
          g.beginPath(); g.arc(cx, cy, size * 0.62, 0, Math.PI * 2); g.fill(); g.stroke();
        }
        g.globalAlpha = rich ? 0.95 : 0.55;
        if(im) g.drawImage(im, cx - size / 2, cy - size / 2, size, size);
        g.restore();
      });
      // zone names: each tries a few spots and shrinks until the whole label sits inside its own zone
      g.textAlign = 'center'; g.textBaseline = 'alphabetic';
      const inZone = (v, mx, my) => !this.raster || this.raster[Math.floor(my / MH * this.RH) * this.RW + Math.floor(mx / MW * this.RW)] === v;
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], z = WAR_ZONES[k], v = this.zoneVal[k];
        const tl = TUNE.labels[k];
        const big = tl && tl[2] ? tl[2] : p.r > 60 ? 25 : p.r > 40 ? 21 : 17;
        let best = null;
        for(let fs = big; fs >= 10 && !(best && best.fit === 1); fs -= 2){
          g.font = `700 ${fs}px Cinzel, serif`;
          const tw = g.measureText(z.name).width / sx, th = (fs + (z.capital ? fs * 0.85 : 0)) / sy;
          if(z.capital){ g.font = `italic 600 ${Math.round(fs * 0.72)}px serif`; }
          for(const f of (tl ? [null] : [0.55, 0.35, 0.8, 0.15, -0.45, 0])){
            const cx = tl ? tl[0] : p.x, cy = tl ? tl[1] + 8 : p.y + p.r * f + (f >= 0 ? 10 : 0);   // label centre (map px); tuned ones stay put and only shrink to fit
            const pts = [[-0.5, 0], [0.5, 0], [0, 0], [-0.5, 1], [0.5, 1], [-0.25, 0.5], [0.25, 0.5], [0, 1]];
            const fit = pts.filter(([a, c]) => inZone(v, cx + a * tw, cy - th * 0.3 + c * th)).length / pts.length;
            if(!best || fit > best.fit || (fit === best.fit && fs > best.fs)) best = { fs, cx, cy, fit };
            if(fit === 1) break;
          }
        }
        const fs = best.fs, yy = best.cy * sy;
        g.font = `700 ${fs}px Cinzel, serif`;
        g.lineWidth = Math.max(3, fs * 0.24); g.strokeStyle = 'rgba(245,232,200,0.9)'; g.fillStyle = '#24160a';
        g.strokeText(z.name, best.cx * sx, yy); g.fillText(z.name, best.cx * sx, yy);
        if(z.capital){
          g.font = `italic 600 ${Math.round(fs * 0.72)}px serif`;
          g.strokeText(z.capital, best.cx * sx, yy + fs * 0.85); g.fillText(z.capital, best.cx * sx, yy + fs * 0.85);
        }
      });
      // darken toward the edges so the curl reads
      const vg = g.createRadialGradient(W / 2, H / 2, H * 0.42, W / 2, H / 2, W * 0.72);
      vg.addColorStop(0, 'rgba(60,30,10,0)'); vg.addColorStop(1, 'rgba(40,20,6,0.55)');
      g.fillStyle = vg; g.fillRect(0, 0, W, H);
      this.tearEdges(g, W, H);
      this.mapTex.needsUpdate = true;
    }

    // rips and tears round the parchment's edge (same every load): a scorched outline, then cut away
    tearEdges(g, W, H){
      let seed = 41; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      const tears = [];
      const edge = (len, at) => {   // at(t, depth) -> [x, y]: t along the edge, depth into the map
        for(let t = 0.04 + rnd() * 0.05; t < 0.96; t += 0.06 + rnd() * 0.12){
          const big = rnd() < 0.4, w = (big ? 50 : 14) + rnd() * (big ? 90 : 30), d = (big ? 45 : 12) + rnd() * (big ? 75 : 22);
          const pts = [at(t - w / len / 2, 0)];
          const n = 3 + Math.floor(rnd() * 4);
          for(let i = 1; i < n; i++){ const f = i / n; pts.push(at(t - w / len / 2 + f * w / len + (rnd() - 0.5) * 0.01, d * (0.35 + rnd() * 0.65) * Math.sin(f * Math.PI))); }
          pts.push(at(t + w / len / 2, 0));
          tears.push(pts);
        }
      };
      // whole corners bitten away, and a few holes worn through near the edge
      [[0, 0, 1, 1], [W, 0, -1, 1], [0, H, 1, -1], [W, H, -1, -1]].forEach(([cx, cy, sx, sy]) => {
        const a = 70 + rnd() * 90, c = 60 + rnd() * 80, pts = [[cx - sx * 4, cy - sy * 4], [cx + sx * a, cy - sy * 4]];
        for(let i = 1; i < 6; i++){ const f = i / 6; pts.push([cx + sx * a * (1 - f) + sx * rnd() * 18, cy + sy * c * f + sy * rnd() * 18]); }
        pts.push([cx - sx * 4, cy + sy * c]); tears.push(pts);
      });
      for(let i = 0; i < 9; i++){
        const side = Math.floor(rnd() * 4), t = 0.08 + rnd() * 0.84, inset = 40 + rnd() * 70, r = 6 + rnd() * 14;
        const [x, y] = [[t * W, inset], [t * W, H - inset], [inset, t * H], [W - inset, t * H]][side];
        const pts = []; for(let k = 0; k < 9; k++){ const a = k / 9 * Math.PI * 2, rr = r * (0.6 + rnd() * 0.6); pts.push([x + Math.cos(a) * rr, y + Math.sin(a) * rr]); }
        tears.push(pts);
      }
      edge(W, (t, d) => [t * W, d - 2]); edge(W, (t, d) => [t * W, H - d + 2]);
      edge(H, (t, d) => [d - 2, t * H]); edge(H, (t, d) => [W - d + 2, t * H]);
      this.tears = tears;
      // a dark, soft-edged shadow drawn exactly where the paper is missing, on a sheet just under the map,
      // so the holes read as holes whatever the table top looks like
      if(!this.holeCanvas){ this.holeCanvas = document.createElement('canvas'); this.holeCanvas.width = W / 2; this.holeCanvas.height = H / 2; }
      const hc = this.holeCanvas.getContext('2d'); hc.clearRect(0, 0, W / 2, H / 2);
      hc.save(); hc.scale(0.5, 0.5); hc.filter = 'blur(10px)'; hc.fillStyle = 'rgba(10,6,2,0.38)';
      tears.forEach(pts => { hc.beginPath(); pts.forEach(([x, y], i) => i ? hc.lineTo(x, y) : hc.moveTo(x, y)); hc.closePath(); hc.fill(); });
      hc.restore();
      if(!this.holeMesh && this.mapGeo){
        this.holeTex = new THREE.CanvasTexture(this.holeCanvas);
        this.holeMesh = new THREE.Mesh(this.mapGeo, new THREE.MeshBasicMaterial({ map: this.holeTex, transparent: true, depthWrite: false }));
        this.holeMesh.rotation.x = -Math.PI / 2; this.holeMesh.position.y = -0.008; this.holeMesh.renderOrder = -1; this.scene.add(this.holeMesh);
      }
      if(this.holeTex) this.holeTex.needsUpdate = true;
      const path = pts => { g.beginPath(); g.moveTo(pts[0][0], pts[0][1]); pts.slice(1).forEach(p => g.lineTo(p[0], p[1])); g.closePath(); };
      g.save();
      g.lineJoin = 'round';
      g.strokeStyle = 'rgba(30,18,6,0.55)'; g.lineWidth = 16; tears.forEach(p => { path(p); g.stroke(); });   // shadow of the curled lip
      g.strokeStyle = 'rgba(236,224,196,0.95)'; g.lineWidth = 8; tears.forEach(p => { path(p); g.stroke(); });  // pale torn-paper fibres
      // the torn-away paper is cut out for real: the board under the map shows through
      g.globalCompositeOperation = 'destination-out'; g.fillStyle = '#000';   // erase fully (destination-out erases by the fill's alpha)
      tears.forEach(p => { path(p); g.fill(); });
      g.globalCompositeOperation = 'source-over';
      g.restore();
    }

    // ----- 3D touches on the map: little mountains, moving water on the lakes and sea -----
    buildTerrain(){
      if(this.terrain) this.scene.remove(this.terrain);
      const T = this.terrain = new THREE.Group(); this.scene.add(T);
      const RW = this.RW, RH = this.RH, R = this.raster;
      let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
      // a free spot inside zone k, clear of its banner, icon, name and scenery (map px)
      const freeSpot = (k, margin, landmark) => {
        const v = this.zoneVal[k], p = WAR_LAYOUT[k];
        for(let tries = 0; tries < 600; tries++){
          const ang = rnd() * Math.PI * 2, dist = p.r * (0.2 + rnd() * 0.7);
          const mx = p.x + Math.cos(ang) * dist, my = p.y + Math.sin(ang) * dist;
          if(!landmark && Math.abs(mx - p.x) < 80 && my > p.y - 30 && my < p.y + 80) continue;   // the banner, icon and name
          if(KEYS.some(o => { const [ax, ay] = anchor(o); return Math.hypot(mx - ax, my - ay) < 40; })) continue;   // any zone's banner
          const sc = SCENERY[k]; if(sc && Math.hypot(mx - p.x - sc.dx, my - p.y - sc.dy) < 48) continue;
          const rx = Math.floor(mx / MW * RW), ry = Math.floor(my / MH * RH), m = Math.ceil(margin / MW * RW);
          let ok = true;
          for(let dy = -m; dy <= m && ok; dy++) for(let dx = -m; dx <= m; dx++){ if(R[(ry + dy) * RW + rx + dx] !== v){ ok = false; break; } }
          if(ok) return [mx, my];
        }
        return null;
      };
      const place = (proto, mx, my, h, rotY) => {
        const o = proto.clone(), at = toWorld(mx, my);
        o.scale.setScalar(h); o.position.set(at.x, this.sheetY(mx, my) - 0.006, at.z); o.rotation.y = rotY; T.add(o); return o;
      };
      const P = this.terrainProtos || {};
      if(P.mountain) Object.keys(MOUNTAINS).forEach(k => {
        const cfg = MOUNTAINS[k], c = TUNE.mountains[k] || freeSpot(k, 18) || freeSpot(k, 10); if(!c) return;
        const proto = cfg.snow ? P.mountainSnow : P.mountain;
        for(let i = 0; i < cfg.count; i++){
          // the first peak is the tallest; the rest crowd round it, smaller, overlapping
          const h = cfg.size * (i ? 0.5 + rnd() * 0.35 : 1);
          const a = rnd() * Math.PI * 2, d = i ? (0.35 + rnd() * 0.45) * cfg.size / PW * MW * 0.9 : 0;
          place(proto, c[0] + Math.cos(a) * d, c[1] + Math.sin(a) * d * 0.8, h, rnd() * 6.28);
        }
      });
      Object.keys(LANDMARKS).forEach(k => {
        const cfg = LANDMARKS[k], proto = P[cfg.model]; if(!proto) return;
        const p = WAR_LAYOUT[k], v = this.zoneVal[k];
        // the spot to the side; step back toward the middle until it's inside the zone
        let c = null;
        for(let f = cfg.side; Math.abs(f) > 0.05 && !c; f *= 0.85){
          const mx = p.x + p.r * f, my = p.y;
          if(R[Math.floor(my / MH * RH) * RW + Math.floor(mx / MW * RW)] === v) c = [mx, my];
        }
        if(TUNE.landmarks[k]) c = TUNE.landmarks[k];
        c = c || freeSpot(k, 6, true); if(!c) return;
        place(proto, c[0], c[1], cfg.size, 0.6);
        // a little ember glow over the crater
        const at = toWorld(c[0], c[1]);
        const light = new THREE.PointLight(0xff5a1a, 0.6, 1.2, 2); light.position.set(at.x, cfg.size * 1.1, at.z); T.add(light);
        this.flames.push({ f: { scale: { y: 0 } }, l: light, s: 1, seed: rnd() * 100, base: 0.6 });
      });
      // water: a second sheet just above the map, showing over lakes (strong) and the sea (faint)
      const mask = document.createElement('canvas'); mask.width = RW; mask.height = RH;
      const mg = mask.getContext('2d'), mi = mg.createImageData(RW, RH);
      for(let i = 0; i < R.length; i++){ const v = R[i] === LAKE ? 200 : 0; /* lakes only: a sea shimmer washed out the painted sea and covered the torn edges */ mi.data[i * 4] = mi.data[i * 4 + 1] = mi.data[i * 4 + 2] = v; mi.data[i * 4 + 3] = 255; }
      mg.putImageData(mi, 0, 0);
      // no water over the torn-away edges: black out the same tear shapes in the mask
      if(this.tears){
        const kx = RW / this.mapCanvas.width, ky = RH / this.mapCanvas.height;
        mg.fillStyle = '#000';
        this.tears.forEach(pts => { mg.beginPath(); pts.forEach(([x, y], i) => i ? mg.lineTo(x * kx, y * ky) : mg.moveTo(x * kx, y * ky)); mg.closePath(); mg.fill(); });
      }
      const ripple = canvasTex(256, 256, (g) => {
        g.fillStyle = '#6f97a8'; g.fillRect(0, 0, 256, 256);
        for(let i = 0; i < 60; i++){
          const x = Math.random() * 256, y = Math.random() * 256, r = 6 + Math.random() * 22;
          const gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, 'rgba(220,240,250,0.55)'); gr.addColorStop(1, 'rgba(220,240,250,0)');
          g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
        }
      });
      ripple.wrapS = ripple.wrapT = THREE.RepeatWrapping; ripple.repeat.set(10, 10);
      const water = new THREE.Mesh(this.mapGeo, new THREE.MeshStandardMaterial({ map: ripple, alphaMap: new THREE.CanvasTexture(mask), transparent: true, roughness: 0.25, metalness: 0.1, depthWrite: false }));
      water.rotation.x = -Math.PI / 2; water.position.y = 0.004; water.renderOrder = 1;
      T.add(water); this.water = ripple;
    }

    // ----- pieces: a banner per zone, outposts / strongholds, fortify walls, troop labels -----
    buildPiece(k){
      const grp = new THREE.Group(); grp.position.copy(zoneWorld(k)); this.scene.add(grp);
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.014, 0.42, 6), new THREE.MeshStandardMaterial({ color: 0x3a2610, metalness: 0.2 }));
      pole.position.set(0.0, 0.21, 0); pole.castShadow = true; grp.add(pole);
      const flagGeo = new THREE.PlaneGeometry(0.2, 0.13, 8, 1);
      const flagMat = new THREE.MeshStandardMaterial({ color: COL.neutralHex, side: THREE.DoubleSide, roughness: 0.8 });
      const flag = new THREE.Mesh(flagGeo, flagMat); flag.position.set(0.1, 0.35, 0); flag.castShadow = true; grp.add(flag);
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.06, 0.03, 12), new THREE.MeshStandardMaterial({ color: 0x5a4632, metalness: 0.4, roughness: 0.5 }));
      base.position.y = 0.015;   // (pedestal removed: banners stand straight on the map)
      // stronghold tower / outpost tent (hidden until built)
      const towerMat = new THREE.MeshStandardMaterial({ color: 0x8a8070, roughness: 0.9 });
      const tower = new THREE.Group();
      const t1 = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.11, 0.28, 10), towerMat); t1.position.y = 0.14; t1.castShadow = true; tower.add(t1);
      const roof = new THREE.Mesh(new THREE.ConeGeometry(0.12, 0.14, 10), new THREE.MeshStandardMaterial({ color: COL.neutralHex })); roof.position.y = 0.35; roof.castShadow = true; tower.add(roof);
      tower.position.set(-0.17, 0, 0.04); grp.add(tower); tower.userData.base = true;
      const tent = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.12, 4), new THREE.MeshStandardMaterial({ color: 0xc9b48a, roughness: 1 }));
      tent.position.set(-0.15, 0.06, 0.05); tent.rotation.y = Math.PI / 4; tent.castShadow = true; grp.add(tent);
      // fortify ring: little stone blocks
      const wall = new THREE.Group();
      for(let i = 0; i < 14; i++){
        const a = i / 14 * Math.PI * 2, s = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.035), towerMat);
        s.position.set(Math.cos(a) * 0.27, 0.03, Math.sin(a) * 0.27); s.rotation.y = -a; s.castShadow = true; wall.add(s);
      }
      grp.add(wall);
      // selection / target ring
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.3, 0.36, 40), new THREE.MeshBasicMaterial({ color: 0xffd36a, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false }));
      ring.rotation.x = -Math.PI / 2; ring.position.y = 0.012; grp.add(ring);
      // label
      const lab = document.createElement('div'); lab.className = 'wb-label'; this.overlay.appendChild(lab);
      const p = { k, grp, pole, flag, flagMat, roof, tower, tent, wall, ring, lab, flagGeo, base: flagGeo.attributes.position.array.slice(), seed: Math.random() * 10 };
      return p;
    }
    setState(s){
      this.state = s;
      if(this.smashed){ this.drawMap(); return; }   // the champion knocked the pieces off: leave the wreckage be
      KEYS.forEach(k => this.syncPiece(k));
      this.drawMap();
    }
    syncPiece(k, zOverride){
      const p = this.pieces[k], z = zOverride || (this.state && this.state.zones[k]);
      if(!z){ p.grp.visible = false; p.lab.style.display = 'none'; return; }
      p.grp.visible = true; p.lab.style.display = '';
      const hex = COL[z.owner + 'Hex'];
      p.flagMat.color.setHex(hex); p.roof.material.color.setHex(hex);
      const fm = this.flagModels && this.flagModels[z.owner];
      if(p.flagFor !== (fm ? z.owner : null)){
        if(p.flagModel){ p.grp.remove(p.flagModel); this.mixers = this.mixers.filter(x => x !== p.flagMixer); p.flagModel = p.flagMixer = null; }
        if(fm){
          p.flagModel = THREE.SkeletonUtils.clone(fm.proto); p.grp.add(p.flagModel);
          if(fm.clip){ p.flagMixer = new THREE.AnimationMixer(p.flagModel); const act = p.flagMixer.clipAction(fm.clip); act.play(); act.time = Math.random() * fm.clip.duration; this.mixers.push(p.flagMixer); }
        }
        p.flagFor = fm ? z.owner : null;
      }
      p.flag.visible = p.pole.visible = !fm;
      const model = z.outpost >= 2 && this.holdModels && this.holdModels[z.owner];
      if(p.holdFor !== (model ? z.owner : null)){
        if(p.hold){ p.grp.remove(p.hold); p.hold = null; }
        if(model){
          p.hold = model.clone(); p.hold.position.set(p.bx || -0.2, 0.002, p.bz || -0.06);
          const th = TUNE.holds[k]; if(th){ if(th.rot) p.hold.rotation.y = th.rot; if(th.scale) p.hold.scale.setScalar(th.scale); }
          p.grp.add(p.hold);
        }
        p.holdFor = model ? z.owner : null;
      }
      const om = z.outpost === 1 && this.holdModels && this.holdModels[z.owner + '_outpost'];
      if(p.postFor !== (om ? z.owner : null)){
        if(p.post){ p.grp.remove(p.post); p.post = null; }
        if(om){ p.post = om.clone(); p.post.position.set(p.bx || -0.17, 0.002, p.bz || 0.05); p.grp.add(p.post); }
        p.postFor = om ? z.owner : null;
      }
      p.tower.visible = z.outpost >= 2 && !model; p.tent.visible = z.outpost === 1 && !om;
      if(p.bx != null){ p.tower.position.set(p.bx, 0, p.bz); p.tent.position.set(p.bx, 0.06, p.bz); }
      const now = this.state ? this.state.clock : 0;
      const fortified = z.fortifyUntil > now, fm2 = fortified && this.holdModels && this.holdModels[z.owner + '_fortify'];
      if(p.fortFor !== (fm2 ? z.owner : null)){
        if(p.fort){ p.grp.remove(p.fort); p.fort = null; }
        if(fm2){ p.fort = fm2.clone(); p.fort.position.set(p.bx != null ? p.bx : -0.2, 0.002, p.bz != null ? p.bz : -0.06); p.grp.add(p.fort); }   // always round the building spot, built or not
        p.fortFor = fm2 ? z.owner : null;
      }
      p.wall.visible = fortified && !fm2;
      // Shield Wall raised: a faint golden dome over the zone's army, holy sparkles drifting over it, until the next attack spends it
      if(z.shield && !p.dome){
        const dm = new THREE.MeshBasicMaterial({ color: 0xffc94a, transparent: true, opacity: 0.2, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
        p.dome = new THREE.Mesh(new THREE.SphereGeometry(0.24, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), dm);
        const rim = new THREE.Mesh(new THREE.TorusGeometry(0.24, 0.006, 6, 48), new THREE.MeshBasicMaterial({ color: 0xffe9a0, transparent: true, opacity: 0.75, depthWrite: false, blending: THREE.AdditiveBlending }));
        rim.rotation.x = Math.PI / 2; p.dome.add(rim);
        // holy sparkles: little four-point stars that twinkle as they drift up over the dome
        if(!this.sparkTex){
          const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d');
          const g = x.createRadialGradient(32, 32, 0, 32, 32, 30); g.addColorStop(0, 'rgba(255,255,235,1)'); g.addColorStop(0.25, 'rgba(255,225,130,0.7)'); g.addColorStop(1, 'rgba(255,200,80,0)');
          x.fillStyle = g; x.fillRect(0, 0, 64, 64);
          x.fillStyle = 'rgba(255,250,220,0.95)'; x.beginPath(); x.moveTo(32, 2); x.lineTo(35, 29); x.lineTo(62, 32); x.lineTo(35, 35); x.lineTo(32, 62); x.lineTo(29, 35); x.lineTo(2, 32); x.lineTo(29, 29); x.closePath(); x.fill();
          this.sparkTex = new THREE.CanvasTexture(c);
        }
        p.dome.userData.sparks = Array.from({ length: 14 }, (_, i) => {
          const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.sparkTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
          p.dome.add(sp); return { sp, a: Math.random() * Math.PI * 2, el: Math.random() * 1.2, ph: Math.random(), sp0: 0.6 + Math.random() * 0.8 };
        }); p.dome.scale.y = 0.75; p.dome.renderOrder = 5; p.grp.add(p.dome); (this.domes = this.domes || new Set()).add(p.dome);
      } else if(!z.shield && p.dome){ p.grp.remove(p.dome); this.domes.delete(p.dome); p.dome = null; }
      if(p.dome) p.dome.position.set(p.bx != null ? p.bx : -0.2, 0.002, p.bz != null ? p.bz : -0.06);   // centred on the fortify wall's spot
      const mobKey = z.owner === 'neutral' ? NEUTRAL_MOBS[WAR_ZONES[k].region] : null, haveMob = mobKey && this.troopProtos && this.troopProtos[mobKey];
      const campN = 0;   // no standing camps (too busy on the map): the monsters only appear to defend in battles
      if(p.campFor !== campN){
        (p.camp || []).forEach(m => { p.grp.remove(m); if(m.userData.mixer) this.mixers = this.mixers.filter(x => x !== m.userData.mixer); });
        p.camp = [];
        for(let i = 0; i < campN; i++){
          const m = this.troop(mobKey); this.scene.remove(m); p.grp.add(m);
          const a = i / Math.max(1, campN) * Math.PI * 2 + 0.6, r = campN > 1 ? 0.07 : 0;
          m.position.set((p.bx != null ? p.bx : -0.15) + Math.cos(a) * r, 0.002, (p.bz != null ? p.bz : 0) + Math.sin(a) * r);
          m.rotation.y = -Math.PI / 2 + (Math.random() - 0.5) * 1.2;   // roughly facing the camera
          m.userData.play('Stand'); p.camp.push(m);
        }
        p.campFor = campN;
      }
      const info = WAR_ZONES[k];
      p.lab.className = 'wb-label ' + z.owner + (this.selected === k ? ' sel' : '');
      // a pet guarding the zone shows as a paw (it defends as one more troop, but isn't moved with the troop slider)
      const S = this.state, guard = S && S.players && Object.values(S.players).find(q => q.pet && q.petZone === k && q.faction === z.owner && !(q.petDown > S.clock));
      p.lab.innerHTML = `<b>${z.ready}</b>⚔${z.fresh ? `<i>+${z.fresh}💤</i>` : ''}${guard ? `<s title="${guard.pet.name || 'Pet'} (level ${guard.pet.level})">🐾</s>` : ''}${z.shield ? '<s>🛡</s>' : ''}`;
      p.lab.title = `${info.name}: ${z.ready} ready, ${z.fresh} fresh`;
    }
    select(k, targets){
      this.selected = k; this.highlights = targets || [];
      this.updateZoneGlow();
      KEYS.forEach(z => this.syncPiece(z));
      this.drawMap();
    }

    // ----- dice -----
    buildDice(){
      const mk = (bg, pip, trim) => [1, 6, 2, 5, 3, 4].map(n => { const t = dieFaceTex(n, bg, pip, trim); t.encoding = THREE.sRGBEncoding; return t; });
      // faction dice: Horde blood-red with bone pips, Alliance royal blue with ivory pips, neutral bone with ink pips
      this.dieTex = { horde: mk('#9e1b14', '#f1e3c2', '#d8a845'), alliance: mk('#1f4aa8', '#f4ecd8', '#e2c060'), neutral: mk('#e6dcc4', '#2a1a0c', '#8a6a3a') };
      this.dieGeo = roundedBox(0.16, 0.028, 4);
      this.dice = [];
    }
    faceQuat(v){
      const e = { 1: [0, 0, Math.PI / 2], 6: [0, 0, -Math.PI / 2], 2: [0, 0, 0], 5: [Math.PI, 0, 0], 3: [-Math.PI / 2, 0, 0], 4: [Math.PI / 2, 0, 0] }[v];
      return new THREE.Quaternion().setFromEuler(new THREE.Euler(e[0], e[1], e[2]));
    }
    // Throw a set of dice from `from` toward `at`, landing showing `vals`
    throwDice(vals, faction, from, at, ms){
      const out = [], tex = this.dieTex[faction] || this.dieTex.neutral;
      vals.forEach((v, i) => {
        const mats = tex.map(t => new THREE.MeshStandardMaterial({ map: t, roughness: 0.32, metalness: 0.08, emissive: 0x000000 }));
        const m = new THREE.Mesh(this.dieGeo, mats); m.castShadow = true; m.userData.mats = mats; m.userData.val = v;
        const side = new THREE.Vector3(at.z - from.z, 0, from.x - at.x).normalize();
        const end = at.clone().add(side.clone().multiplyScalar((i - (vals.length - 1) / 2) * 0.22)); end.y = 0.08;
        const start = from.clone(); start.y = 0.9;
        const qEnd = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), (Math.random() - 0.5) * 0.9).multiply(this.faceQuat(v));
        const spin = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
        const sh = new THREE.Mesh(new THREE.CircleGeometry(0.1, 20), new THREE.MeshBasicMaterial({ map: this.glow, color: 0x000000, transparent: true, opacity: 0, depthWrite: false }));
        sh.rotation.x = -Math.PI / 2; sh.position.set(end.x, 0.006, end.z); this.scene.add(sh); m.userData.shadow = sh;
        this.scene.add(m); this.dice.push(m);
        let landed = false;
        out.push(this.animate(ms, t => {
          const e = easeOut(t);
          m.position.lerpVectors(start, end, e);
          // an arc, then two shrinking bounces
          const bounce = t < 0.62 ? Math.sin(t / 0.62 * Math.PI) * 0.7 : t < 0.84 ? Math.sin((t - 0.62) / 0.22 * Math.PI) * 0.09 : Math.sin((t - 0.84) / 0.16 * Math.PI) * 0.025;
          m.position.y = 0.08 + bounce;
          m.quaternion.copy(qEnd).premultiply(new THREE.Quaternion().setFromAxisAngle(spin, (1 - e) * 16));
          sh.position.x = m.position.x; sh.position.z = m.position.z;
          const hgt = m.position.y - 0.08; sh.material.opacity = 0.55 * Math.max(0, 1 - hgt * 1.6); sh.scale.setScalar(1 + hgt * 1.5);
          if(!landed && t > 0.6){ landed = true; this.sparks(m.position.clone().setY(0.02), 0xffd28a, 10, 0.5); }
        }));
      });
      return Promise.all(out);
    }
    // compare the dice pair by pair: winners flare gold, losers go dark and sink a little
    async judgeDice(att, def, bonus){
      const A = this.dice.filter(d => att.includes(d)), D = this.dice.filter(d => def.includes(d));
      const pairs = Math.min(A.length, D.length);
      const order = list => list.slice().sort((p, q) => q.userData.val - p.userData.val);
      const a = order(A), d = order(D);
      for(let i = 0; i < pairs; i++){
        const attWins = a[i].userData.val > d[i].userData.val + (i === 0 ? bonus : 0);
        const win = attWins ? a[i] : d[i], lose = attWins ? d[i] : a[i];
        win.userData.mats.forEach(mm => { mm.emissive.setHex(0xffc040); mm.emissiveMap = mm.map; mm.emissiveIntensity = 0; mm.needsUpdate = true; });
        this.animate(500, t => { win.userData.mats.forEach(mm => { mm.emissiveIntensity = Math.sin(Math.min(1, t * 2) * Math.PI / 2) * 0.18; }); win.position.y = 0.08 + Math.sin(t * Math.PI) * 0.05; });
        this.animate(500, t => { lose.userData.mats.forEach(mm => mm.color.setScalar(1 - 0.55 * t)); lose.position.y = 0.08 - 0.02 * t; });
        this.sparks(win.position.clone().setY(0.12), 0xffc050, 14, 0.8);
        await this.wait(160);
      }
      // the unmatched extra dice fade a touch
      a.slice(pairs).concat(d.slice(pairs)).forEach(x => x.userData.mats.forEach(mm => mm.color.setScalar(0.7)));
    }
    // a burst of glowing sparks that arc up and fall (additive points with simple gravity)
    sparks(at, color, n, power){
      const pos = new Float32Array(n * 3), vel = [];
      for(let i = 0; i < n; i++){
        pos.set([at.x, at.y, at.z], i * 3);
        const a = Math.random() * Math.PI * 2, up = 0.6 + Math.random() * 0.8;
        vel.push(new THREE.Vector3(Math.cos(a) * (0.3 + Math.random() * 0.5), up, Math.sin(a) * (0.3 + Math.random() * 0.5)).multiplyScalar(power));
      }
      const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const pts = new THREE.Points(geo, new THREE.PointsMaterial({ map: this.glow, color, size: 0.05, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
      this.scene.add(pts); let last = 0;
      return this.animate(700, t => {
        const dt = (t - last) * 0.7; last = t; const pa = geo.attributes.position;
        for(let i = 0; i < n; i++){ vel[i].y -= 2.2 * dt; pa.setXYZ(i, pa.getX(i) + vel[i].x * dt, Math.max(0.005, pa.getY(i) + vel[i].y * dt), pa.getZ(i) + vel[i].z * dt); }
        pa.needsUpdate = true; pts.material.opacity = 1 - t * t;
      }).then(() => { this.scene.remove(pts); geo.dispose(); });
    }
    clearDice(){ this.dice.forEach(d => { this.scene.remove(d); if(d.userData.shadow) this.scene.remove(d.userData.shadow); }); this.dice = []; }

    // ----- capture: a column of faction light, a fire-and-dust shockwave, rising embers, and the zone's
    // colour sweeping in from the centre -----
    async captureFx(k, faction){
      const at = zoneWorld(k), col = faction === 'horde' ? 0xff4a24 : 0x4a8cff, hot = faction === 'horde' ? 0xffb050 : 0xbfe0ff;
      const fit = (this.pieces[k] && this.pieces[k].fit) || 1;
      // light column
      const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.07 * fit, 0.16 * fit, 1.6, 24, 1, true), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
      beam.position.set(at.x, 0.8, at.z); this.scene.add(beam);
      const core = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glow, color: hot, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      core.position.set(at.x, 0.25, at.z); this.scene.add(core);
      const light = new THREE.PointLight(col, 0, 4, 2); light.position.set(at.x, 0.6, at.z); this.scene.add(light);
      // two shockwave rings: a bright inner one and a dusty outer one
      const ring = (color, w, ms, reach, op) => {
        const r = new THREE.Mesh(new THREE.RingGeometry(0.85, 1, 64), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: op, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
        r.rotation.x = -Math.PI / 2; r.position.set(at.x, 0.015, at.z); this.scene.add(r);
        return this.animate(ms, t => { const s = (0.08 + easeOut(t) * reach) * fit; r.scale.set(s, s, s); r.material.opacity = op * (1 - t); }).then(() => this.scene.remove(r));
      };
      this.shake(380, 0.1);
      ring(hot, 0.15, 700, 0.42, 0.55); setTimeout(() => ring(col, 0.3, 1000, 0.7, 0.25), 120 / this.speed);
      this.sparks(at.clone().setY(0.05), hot, 40, 0.7 * fit);
      // embers drifting up the column
      const n = 36, pos = new Float32Array(n * 3), seeds = [];
      for(let i = 0; i < n; i++){ const a = Math.random() * 6.28, r = Math.random() * 0.25 * fit; pos.set([at.x + Math.cos(a) * r, Math.random() * 0.2, at.z + Math.sin(a) * r], i * 3); seeds.push(0.4 + Math.random() * 0.8); }
      const eg = new THREE.BufferGeometry(); eg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const embers = new THREE.Points(eg, new THREE.PointsMaterial({ map: this.glow, color: hot, size: 0.04, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
      this.scene.add(embers);
      await this.animate(1500, t => {
        const up = Math.sin(Math.min(1, t * 3) * Math.PI / 2), fade = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4;
        beam.material.opacity = 0.22 * up * fade; beam.scale.set(1 + t * 0.4, 0.3 + up * 0.7, 1 + t * 0.4);
        core.scale.setScalar((0.25 + up * 0.5) * fit); core.material.opacity = 0.7 * fade;
        light.intensity = 1.4 * up * fade;
        const pa = eg.attributes.position;
        for(let i = 0; i < n; i++) pa.setY(i, (pa.getY(i) + 0.012 * seeds[i] * this.speed) % 1.6);
        pa.needsUpdate = true; embers.material.opacity = fade;
      });
      this.scene.remove(beam, core, light, embers); eg.dispose();
    }

    // ----- generic tween helper (speed-aware) -----
    animate(ms, fn){
      return new Promise(res => { this.anims.push({ t0: performance.now(), ms: ms / this.speed, fn, res }); });
    }
    wait(ms){ return sleep(ms / this.speed); }

    // ----- camera -----
    applyCamera(){
      const c = this.cam, sp = Math.sin(c.polar), dist = c.dist;
      this.camera.position.set(c.target.x + dist * sp * Math.sin(c.az), c.target.y + dist * Math.cos(c.polar), c.target.z + dist * sp * Math.cos(c.az));
      this.camera.position.add(this.shakeOff);
      this.camera.lookAt(this.shakeOff.clone().add(c.target));
    }
    tweenCam(to, ms){
      const from = { target: this.cam.target.clone(), dist: this.cam.dist, polar: this.cam.polar, az: this.cam.az };
      const tgt = to.target || from.target;
      return this.animate(ms, t => {
        const e = ease(t);
        this.cam.target.lerpVectors(from.target, tgt, e);
        ['dist', 'polar', 'az'].forEach(p => { if(to[p] != null) this.cam[p] = from[p] + (to[p] - from[p]) * e; });
      });
    }
    // resolves once every model and texture has finished loading (and stayed finished for a moment, since
    // some loads only start after others land), or after 15s whatever happens
    whenLoaded(){
      const LM = THREE.DefaultLoadingManager;
      return new Promise(res => {
        const t0 = performance.now(); let quietSince = 0;
        const check = () => {
          const busy = this._loading > 0 || !this.baseImg || !this.raster;
          if(!busy){ quietSince = quietSince || performance.now(); if(performance.now() - quietSince > 900) return res(); }
          else quietSince = 0;
          if(performance.now() - t0 > 15000) return res();
          setTimeout(check, 150);
        };
        check();
      });
    }
    async intro(){
      // stand in the doorway, then sweep down over the table
      this.cam = { target: new THREE.Vector3(0, 0.5, -2), dist: 17, polar: 1.32, az: 0.0 };
      this.applyCamera();
      await this.tweenCam(this.homeView(), 3200);
    }
    // the resting view of the whole board; on a tall phone screen look down from higher up, so the map fills the
    // width and as much of the height as a square map can (instead of a strip of table under a lot of room)
    homeView(){
      const portrait = (this.camera.aspect || 1.5) < 0.8;
      return portrait ? { target: new THREE.Vector3(0, 0, 0.2), dist: 12.5, polar: 0.28, az: 0 } : { target: new THREE.Vector3(0, 0, 0.3), dist: 11.5, polar: 0.62, az: 0 };
    }
    focusZones(keys, ms, dist){
      const v = new THREE.Vector3(); keys.forEach(k => v.add(zoneWorld(k))); v.multiplyScalar(1 / keys.length);
      let spread = 0; keys.forEach(k => { spread = Math.max(spread, zoneWorld(k).distanceTo(v)); });
      const d = dist || Math.max(3.2, spread * 2.6 + 2.6);
      // a panel covering the bottom of the screen (phones): aim lower so the zones land in the visible top part
      if(this.insetBottom) v.z += this.insetBottom * d * 0.55;
      return this.tweenCam({ target: v, dist: d, polar: 0.78 }, ms || 900);
    }
    overview(ms){ return this.tweenCam(this.homeView(), ms || 900); }
    continent(which){
      return this.tweenCam({ target: which === 'kalimdor' ? new THREE.Vector3(-PW * 0.25, 0, 0.1) : new THREE.Vector3(PW * 0.25, 0, 0.1), dist: 7.6, polar: 0.62, az: 0 }, 1000);
    }
    shake(ms, amt){
      // a jitter added on top of the camera, so it can overlap camera tweens safely
      return this.animate(ms, t => { const a = amt * (1 - t); this.shakeOff.set((Math.random() - 0.5) * a, 0, (Math.random() - 0.5) * a); })
        .then(() => this.shakeOff.set(0, 0, 0));
    }

    // ----- effects -----
    floatText(k, text, cls){
      const el = document.createElement('div'); el.className = 'wb-float ' + (cls || ''); el.textContent = text; this.overlay.appendChild(el);
      const p = zoneWorld(k); p.y = 0.45;
      const item = { el, p, t0: performance.now() };
      (this.floats = this.floats || []).push(item);
      setTimeout(() => { el.remove(); this.floats = this.floats.filter(f => f !== item); }, 1800 / this.speed);
    }
    flash(pos, color, size){
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glow, color, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      s.position.copy(pos); s.position.y = 0.25; this.scene.add(s);
      return this.animate(500, t => { const k = size * (0.4 + t); s.scale.set(k, k, 1); s.material.opacity = 1 - t; }).then(() => this.scene.remove(s));
    }
    pulseRing(k, color){
      const r = new THREE.Mesh(new THREE.RingGeometry(0.2, 0.26, 40), new THREE.MeshBasicMaterial({ color, transparent: true, side: THREE.DoubleSide, depthWrite: false }));
      r.rotation.x = -Math.PI / 2; r.position.copy(zoneWorld(k)); r.position.y = 0.02; this.scene.add(r);
      return this.animate(900, t => { const s = 1 + t * 3; r.scale.set(s, s, s); r.material.opacity = 1 - t; }).then(() => this.scene.remove(r));
    }
    arcCurve(a, b, h){
      const A = zoneWorld(a), B = zoneWorld(b); A.y = B.y = 0.06;
      const mid = A.clone().add(B).multiplyScalar(0.5); mid.y = h != null ? h : 0.25 + A.distanceTo(B) * 0.25;
      return new THREE.QuadraticBezierCurve3(A, mid, B);
    }
    drawArrow(curve, color){
      const geo = new THREE.TubeGeometry(curve, 48, 0.03, 8, false);
      const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9 });
      const tube = new THREE.Mesh(geo, mat); this.scene.add(tube);
      const head = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.18, 10), mat); this.scene.add(head);
      const total = geo.index.count;
      geo.setDrawRange(0, 0);
      const grow = this.animate(650, t => {
        const e = easeOut(t); geo.setDrawRange(0, Math.floor(total * e / 6) * 6);
        const p = curve.getPoint(Math.max(0.01, e)), tan = curve.getTangent(Math.max(0.01, e));
        head.position.copy(p); head.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), tan);
      });
      return { grow, remove: () => this.animate(400, t => { mat.opacity = 0.9 * (1 - t); }).then(() => { this.scene.remove(tube, head); geo.dispose(); }) };
    }
    // ----- WoW candles on the table corners: tall Stormwind funeral candles and Kul Tiran candle clusters.
    // Their flame cards burn additively; the glow sprite and light move to the top of each flame. -----
    loadCandles(){
      if(!THREE.GLTFLoader || !this.candleFx) return;
      const M = window.WAR_CANDLES || { tall: 'models/war/candle-tall.gltf', cluster: 'models/war/candle-cluster.gltf' };
      const H = { tall: 1.5, cluster: 0.65 }, protos = {}; let left = 2;
      const place = () => {
        this.candleFx.forEach((cf, i) => {
          const kind = (cf.kind = cf.kind || (Math.random() < 0.5 ? 'tall' : 'cluster')), P = protos[kind] || protos.tall || protos.cluster; if(!P) return;
          const m = P.clone(); m.position.set(cf.x, 0, cf.z); m.rotation.y = Math.random() * Math.PI * 2; this.scene.add(m);
          if(this.drawnCandles[i]) this.drawnCandles[i].visible = false;
          const top = (H[kind] || H.tall || H.cluster) * 0.95; cf.f.position.y = top - 0.14; cf.f.scale.set(0.24, 0.3, 1); cf.l.position.y = top;   // the glow sits round the flame, not above it
        });
      };
      Object.keys(M).forEach(kind => new THREE.GLTFLoader().load(M[kind], gltf => {
        const m = gltf.scene;
        const skinned = []; m.traverse(o => { if(o.isSkinnedMesh) skinned.push(o); });
        skinned.forEach(o => { const q = new THREE.Mesh(o.geometry, o.material); q.name = o.name; q.position.copy(o.position); q.quaternion.copy(o.quaternion); q.scale.copy(o.scale); o.parent.add(q); o.parent.remove(o); });
        m.traverse(o => { if(!o.isMesh) return;
          if(/1380452|1380453|1829580/.test(o.material.name)) o.material = new THREE.MeshBasicMaterial({ map: o.material.map, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
          else { o.castShadow = true; o.receiveShadow = true; }
        });
        const box = new THREE.Box3().setFromObject(m), s = H[kind] / (box.max.y - box.min.y);
        m.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
        const holder = new THREE.Group(), inner = new THREE.Group(); inner.add(m); inner.scale.setScalar(s); holder.add(inner);
        protos[kind] = holder; if(--left === 0) place();
      }, undefined, err => { console.warn(kind + ' candle failed to load:', err); if(--left === 0) place(); }));
    }

    // ----- Horde fortify: a round palisade built from the outpost pieces - a gate at the front, log wall
    // sections round the rest, a stake at every joint. Built once, then cloned like the other models. -----
    loadHordeFortify(){
      if(!THREE.GLTFLoader) return;
      const M = window.WAR_PALISADE || { wall: 'models/war/horde-palisade-04.gltf', post: 'models/war/horde-palisade-06.gltf', gate: 'models/war/horde-palisade-07.gltf' };
      const P = {}; let left = 3;
      const build = () => {
        if(!P.wall) return;
        const ring = new THREE.Group(), R = 15, sections = 9;   // model units; the wall pieces are ~8.8 long
        for(let i = 0; i < sections; i++){
          const a = (i + 0.5) / (sections + 1.6) * Math.PI * 2 + Math.PI / 2 + 0.55;   // leave a gap at the front for the gate
          const piece = P.wall.clone(); piece.position.set(Math.cos(a) * R, 0, Math.sin(a) * R); piece.rotation.y = -a + Math.PI / 2; ring.add(piece);   // spikes facing outward
          if(P.post){ const b2 = a + Math.PI / (sections + 1.6); const post = P.post.clone(); post.position.set(Math.cos(b2) * R, 0, Math.sin(b2) * R); ring.add(post); }
        }
        if(P.gate){ const gate = P.gate.clone(); gate.scale.setScalar(0.75); gate.position.set(0, 0, R); ring.add(gate); }   // gate facing the camera side
        const s = 0.31 / R; ring.scale.setScalar(s);
        const holder = new THREE.Group(); holder.add(ring);
        (this.holdModels = this.holdModels || {}).horde_fortify = holder;
        KEYS.forEach(k => this.syncPiece(k));
      };
      Object.keys(M).forEach(k => new THREE.GLTFLoader().load(M[k], gltf => {
        const m = gltf.scene;
        const sk = []; m.traverse(o => { if(o.isSkinnedMesh) sk.push(o); });
        sk.forEach(o => { const q = new THREE.Mesh(o.geometry, o.material); q.position.copy(o.position); q.quaternion.copy(o.quaternion); q.scale.copy(o.scale); o.parent.add(q); o.parent.remove(o); });
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.receiveShadow = true; o.material.side = THREE.DoubleSide; o.material.alphaTest = 0.4; o.material.transparent = false; } });
        const box = new THREE.Box3().setFromObject(m);
        m.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
        const g = new THREE.Group(); g.add(m); P[k] = g;
        if(--left === 0) build();
      }, undefined, err => { console.warn('palisade piece failed to load:', err); if(--left === 0) build(); }));
    }

    // Each zone's pieces (banner, buildings, fortify wall) are scaled to the room around their anchor: full size
    // in big zones, smaller in tight ones so nothing spills over a border. Footprint at full size ~0.42 units.
    fitPieces(){
      if(!this.raster) return;
      const RW = this.RW, RH = this.RH, R = this.raster, FOOT = 0.34, pxPerUnit = RW / PW;
      KEYS.forEach(k => {
        const v = this.zoneVal[k], [ax, ay] = anchor(k), cx = Math.floor(ax / MW * RW), cy = Math.floor(ay / MH * RH);
        let clear = 0;
        for(let r = 1; r < 80 && !clear; r++){
          for(let a = 0; a < 24; a++){
            const x = Math.round(cx + Math.cos(a / 24 * Math.PI * 2) * r), y = Math.round(cy + Math.sin(a / 24 * Math.PI * 2) * r);
            if(x < 0 || y < 0 || x >= RW || y >= RH || R[y * RW + x] !== v){ clear = r; break; }
          }
        }
        const room = (clear || 80) / pxPerUnit;   // distance to the nearest border, in world units
        let s = Math.max(0.6, Math.min(1, room / FOOT));
        let best = null;
        for(;;){   // shrink a cramped zone's pieces (down to 0.4) until its fortify wall fits inside it
        // where the building stands: 0.2 units from the banner (scaled), in the direction with the most room
        const inside = (wx, wz, rad) => {   // world offset from the anchor -> is a circle of radius rad (world) all in zone?
          const px = cx + wx * pxPerUnit, py = cy + wz * (RH / PH), rr = rad * pxPerUnit;
          for(let a = 0; a < 16; a++) for(const f of [0, 0.5, 1]){
            const x = Math.round(px + Math.cos(a / 16 * Math.PI * 2) * rr * f), y = Math.round(py + Math.sin(a / 16 * Math.PI * 2) * rr * f);
            if(x < 0 || y < 0 || x >= RW || y >= RH || R[y * RW + x] !== v) return false;
          }
          return true;
        };
        // where the building stands - and the fortify wall, which is always centred on it: search the zone near
        // the banner for the spot where the building fits fully inside and as much of the wall ring as possible does too
        const frac = (wx, wz, rad, n) => {   // share of a circle's rim (radius rad, world) that lies inside the zone
          const px = cx + wx * pxPerUnit, py = cy + wz * (RH / PH), rr = rad * pxPerUnit; let ok = 0;
          for(let a = 0; a < n; a++){ const x = Math.round(px + Math.cos(a / n * Math.PI * 2) * rr), y = Math.round(py + Math.sin(a / n * Math.PI * 2) * rr); if(x >= 0 && y >= 0 && x < RW && y < RH && R[y * RW + x] === v) ok++; }
          return ok / n;
        };
        best = null; let bestScore = -1e9;
        const RING = 0.33 * s, REACH = 0.42 * s, STEP = 0.03 * s;
        for(let oz = -REACH; oz <= REACH; oz += STEP) for(let ox = -REACH; ox <= REACH; ox += STEP){
          const d = Math.hypot(ox, oz); if(d > REACH || d < 0.1 * s) continue;   // near the banner, but not on top of it
          if(!inside(ox, oz, 0.13 * s)) continue;
          const score = frac(ox, oz, RING, 32) * 2 + frac(ox, oz, RING * 0.6, 20) - d / REACH * 0.25 + (ox < 0 ? 0.05 : 0);
          if(score > bestScore){ bestScore = score; best = [ox, oz]; }
        }
        if(!best) for(let i = 0; i < 12 && !best; i++){ const a = Math.PI + i / 12 * Math.PI * 2, d = 0.15 * s; if(inside(Math.cos(a) * d, Math.sin(a) * d * 0.6, 0.09 * s)) best = [Math.cos(a) * d, Math.sin(a) * d * 0.6]; }
        this.pieces[k].ringFit = best ? frac(best[0], best[1], RING, 64) : 0;
        if(this.pieces[k].ringFit >= 0.85 || s <= 0.4)break;
        s = Math.max(0.4, s - 0.05);
        }
        this.pieces[k].grp.scale.setScalar(s); this.pieces[k].fit = s;
        best = best || [-0.12 * s, 0];
        const hAt = TUNE.holds[k] && TUNE.holds[k].at;   // a hand-placed building spot wins
        if(hAt){ const an = anchor(k); best = [(hAt[0] - an[0]) / MW * PW, (hAt[1] - an[1]) / MH * PH]; }
        this.pieces[k].bx = best[0] / s; this.pieces[k].bz = best[1] / s;   // stored in the group's (scaled) space
        // where a guarding pet stands, for each size of pet: clear of the building and its fortify wall (and the
        // banner), inside the zone, preferring the front (toward the camera) and as close in as it fits
        const share = (wx, wz, rad) => {
          const px = cx + wx * pxPerUnit, py = cy + wz * (RH / PH), rr = rad * pxPerUnit; let ok = 0, n = 0;
          for(let a = 0; a < 20; a++) for(const f of [0, 0.6, 1]){
            n++; const x = Math.round(px + Math.cos(a / 20 * Math.PI * 2) * rr * f), y = Math.round(py + Math.sin(a / 20 * Math.PI * 2) * rr * f);
            if(x >= 0 && y >= 0 && x < RW && y < RH && R[y * RW + x] === v) ok++;
          }
          return ok / n;
        };
        this.pieces[k].petSpot = {};
        Object.keys(PET_SPAN).forEach(stage => {
          const rad = PET_SPAN[stage] / 2, clearB = (0.34 + rad * 0.8) * s, clearF = (0.1 + rad * 0.7) * s;
          let pick = null, top = -1e9;
          for(let i = 0; i < 24; i++){
            const da = (i % 2 ? 1 : -1) * Math.ceil(i / 2) * (Math.PI / 12), a = Math.PI / 2 + da;   // fanning out from straight in front
            for(let d = clearB; d <= clearB + 0.5 * s; d += 0.03 * s){
              const x = best[0] + Math.cos(a) * d, z = best[1] + Math.sin(a) * d;
              if(Math.hypot(x, z) < clearF) continue;
              const score = share(x, z, rad * 0.85 * s) * 4 - Math.abs(da) * 0.35 - (d - clearB) / s * 0.8;
              if(score > top){ top = score; pick = [x, z]; }
            }
          }
          if(pick) this.pieces[k].petSpot[stage] = [pick[0] / s, pick[1] / s];
        });
        this.pieces[k].holdFor = this.pieces[k].postFor = this.pieces[k].fortFor = this.pieces[k].campFor = undefined;   // re-place on next sync
        if(this.state) this.syncPiece(k);
      });
      // pets already standing move to their zone's new spot
      Object.values(this.petModels || {}).forEach(rec => {
        const sp = rec.obj && this.pieces[rec.zone] && this.pieces[rec.zone].petSpot && this.pieces[rec.zone].petSpot[rec.stage];
        if(sp) rec.obj.position.set(sp[0], 0.002, sp[1]);
      });
    }

    // ----- selection glow: a bright rim just inside the selected zone's border that fades inward, with a soft
    // halo just outside; valid targets get a pulsing ember rim. Two additive sheets over the map. -----
    zoneGlowCanvas(vals, inner, outer){
      const RW = this.RW, RH = this.RH, R = this.raster, N = RW * RH, inS = new Uint8Array(256);
      vals.forEach(v => { inS[v] = 1; });
      const din = new Int16Array(N).fill(-1), dout = new Int16Array(N).fill(-1), q1 = [], q2 = [];
      for(let y = 0; y < RH; y++) for(let x = 0; x < RW; x++){
        const i = y * RW + x, s = inS[R[i]];
        const edge = (x > 0 && inS[R[i - 1]] !== s) || (x < RW - 1 && inS[R[i + 1]] !== s) || (y > 0 && inS[R[i - RW]] !== s) || (y < RH - 1 && inS[R[i + RW]] !== s);
        if(!edge) continue;
        if(s){ din[i] = 0; q1.push(i); } else { dout[i] = 0; q2.push(i); }
      }
      const grow = (q, d, want, lim) => {
        for(let h = 0; h < q.length; h++){
          const i = q[h], x = i % RW, y = (i / RW) | 0; if(d[i] >= lim) continue;
          [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([dx, dy]) => { const nx = x + dx, ny = y + dy; if(nx < 0 || ny < 0 || nx >= RW || ny >= RH) return; const j = ny * RW + nx; if(d[j] < 0 && inS[R[j]] === want){ d[j] = d[i] + 1; q.push(j); } });
        }
      };
      grow(q1, din, 1, inner); grow(q2, dout, 0, outer);
      const c = document.createElement('canvas'); c.width = RW; c.height = RH;
      const g = c.getContext('2d'), im = g.createImageData(RW, RH), d = im.data;
      for(let i = 0; i < N; i++){
        let a = 0;
        if(din[i] >= 0) a = din[i] <= 1 ? 0.95 : Math.pow(1 - din[i] / inner, 2.2) * 0.4;
        else if(dout[i] >= 0) a = Math.pow(1 - dout[i] / outer, 2) * 0.45;
        d[i * 4] = d[i * 4 + 1] = d[i * 4 + 2] = 255; d[i * 4 + 3] = Math.round(a * 255);
      }
      g.putImageData(im, 0, 0); return c;
    }
    updateZoneGlow(){
      if(!this.raster || !this.mapGeo) return;
      const mk = (color) => {
        const m = new THREE.Mesh(this.mapGeo, new THREE.MeshBasicMaterial({ color, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0 }));
        m.rotation.x = -Math.PI / 2; m.position.y = 0.006; m.renderOrder = 2; this.scene.add(m); return m;
      };
      if(!this.selGlow){ this.selGlow = mk(0xffd36a); this.tgtGlow = mk(0xff6a3a); }
      const set = (mesh, vals, inner, outer) => {
        if(mesh.material.map){ mesh.material.map.dispose(); mesh.material.map = null; }
        if(!vals.length){ mesh.visible = false; return; }
        const t = new THREE.CanvasTexture(this.zoneGlowCanvas(vals, inner, outer)); t.encoding = THREE.sRGBEncoding;
        mesh.material.map = t; mesh.material.needsUpdate = true; mesh.visible = true;
      };
      set(this.selGlow, this.selected ? [this.zoneVal[this.selected]] : [], 9, 5);
      set(this.tgtGlow, (this.highlights || []).map(k => this.zoneVal[k]).filter(Boolean), 6, 3);
    }

    // ----- troop figures: the animated Alliance footman / Horde grunt. wow.export leaves worn gear loose;
    // tools/attach_gear.py worked out each piece's bone and exact placement (from the posed OBJ export) and
    // stored it in the node's extras, so here every piece is pinned to its bone and moves with the animation. -----
    loadTroops(){
      if(!THREE.GLTFLoader || !THREE.SkeletonUtils) return;
      const M = window.WAR_TROOPS || { alliance: 'models/war/troop-alliance.gltf', horde: 'models/war/troop-horde.gltf',
        // neutral camps: each region's own monsters
        mob_gnoll: 'models/war/mob-gnoll.gltf', mob_centaur: 'models/war/mob-centaur.gltf', mob_furbolg: 'models/war/mob-furbolg.gltf', mob_ghoul: 'models/war/mob-ghoul.gltf',
        mob_silithid: 'models/war/mob-silithid.gltf', mob_defias: 'models/war/mob-defias.gltf' };
      this.troopProtos = {};
      Object.keys(M).forEach(f => new THREE.GLTFLoader().load(M[f], gltf => {
        const m = gltf.scene; m.updateMatrixWorld(true);
        let skel = null; m.traverse(o => { if(o.isSkinnedMesh && !skel) skel = o.skeleton; });
        const steel = new THREE.MeshStandardMaterial({ color: 0x9aa3b0, metalness: 0.6, roughness: 0.4, side: THREE.DoubleSide });
        const gear = []; m.traverse(o => { if(o.isMesh && o.userData.attach) gear.push(o); });
        gear.forEach(o => {
          const a = o.userData.attach, bone = skel && skel.bones[a.joint]; if(!bone) return;
          o.parent.remove(o); bone.add(o);
          o.matrixAutoUpdate = false; o.matrix.fromArray(a.matrix);   // may mirror, so it's kept as a raw matrix
          // pieces exported with the body's skin texture had no texture of their own: plain steel instead
          if(o.material && o.material.map && /^data-1/.test(o.material.name)) o.material = steel;
        });
        m.traverse(o => { if(o.isMesh){ o.castShadow = true; o.frustumCulled = false; if(/EyeGlow/i.test(o.name)) o.visible = false;
          if(/HeadSwap/i.test(o.name) && gear.some(g => /^Head_/.test(g.name))) o.visible = false;   // the bare head WoW swaps out under a helm
          if(o.material.map){ o.material.alphaTest = 0.4; o.material.transparent = false; } o.material.side = THREE.DoubleSide; } });
        const box = new THREE.Box3(); m.traverse(o => { if(o.isSkinnedMesh) box.expandByObject(o); });
        const s = 0.17 / (box.max.y - box.min.y); m.position.y = -box.min.y;
        const inner = new THREE.Group(); inner.add(m); inner.scale.setScalar(s);
        this.troopProtos[f] = { proto: inner, clips: gltf.animations };
      }, undefined, err => console.warn(f + ' troops failed to load, using plain tokens:', err)));
    }
    troop(faction){
      const mob = /^neutral:/.test(faction) ? NEUTRAL_MOBS[faction.slice(8)] : null;
      if(mob) faction = mob;
      const P = this.troopProtos && this.troopProtos[faction];
      const holder = new THREE.Group();
      if(!P){
        const mat = new THREE.MeshStandardMaterial({ color: COL[faction + 'Hex'] || COL.neutralHex, metalness: 0.3, roughness: 0.5 });
        const b1 = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 0.1, 8), mat); b1.position.y = 0.05; holder.add(b1);
        const hd = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 6), mat); hd.position.y = 0.12; holder.add(hd);
        holder.userData.play = () => 0; this.scene.add(holder); return holder;
      }
      const fig = THREE.SkeletonUtils.clone(P.proto); holder.add(fig);
      const mixer = new THREE.AnimationMixer(fig); let cur = null;
      holder.userData.mixer = mixer; (this.mixers = this.mixers || []).push(mixer);
      holder.userData.play = (name, once) => {
        const c = (CLIP_ALIASES[name] || [name]).map(n => P.clips.find(x => x.name === n)).find(Boolean); if(!c) return 0;
        const a = mixer.clipAction(c); a.reset(); a.setLoop(once ? THREE.LoopOnce : THREE.LoopRepeat); a.clampWhenFinished = !!once;
        if(!once) a.time = Math.random() * c.duration;
        if(cur && cur !== a) a.crossFadeFrom(cur, 0.2, false);
        a.play(); cur = a; return c.duration * 1000;
      };
      holder.userData.face = (dx, dz) => { holder.rotation.y = Math.atan2(-dz, dx); };   // WoW models face +x
      holder.userData.play('Ready1H');
      this.scene.add(holder); return holder;
    }
    marchTokens(curve, n, faction, ms){
      const count = Math.min(5, Math.max(1, n)), toks = [];
      for(let i = 0; i < count; i++){ const m = this.troop(faction); m.userData.play('Run'); toks.push(m); }
      return this.animate(ms, t => {
        toks.forEach((m, i) => {
          const tt = Math.max(0, Math.min(1, t * 1.3 - i * 0.06)), e = ease(tt);
          const p = curve.getPoint(e), d = curve.getTangent(Math.min(0.999, Math.max(0.001, e)));
          m.position.copy(p); m.position.y = Math.max(0.0, p.y - 0.06);
          m.position.x += (i % 3 - 1) * 0.05; m.position.z += (Math.floor(i / 3) - 0.5) * 0.06;
          if(m.userData.face) m.userData.face(d.x, d.z);
        });
      }).then(() => { toks.forEach(m => m.userData.play('Ready1H')); return toks; });
    }
    // Two armies facing each other in ranks between the zones. cull(attAlive, defAlive) drops figures (Death clip,
    // then they sink and vanish) to match how many troops each side still has; finish() sends the survivors home
    // (or into the captured zone) and clears the field.
    async formArmies(A, B, attN, defN, attF, defF){
      const CAP = 10, dir = B.clone().sub(A); dir.y = 0; const len = dir.length(); dir.normalize();
      const side = new THREE.Vector3(-dir.z, 0, dir.x), gap = 0.075, perRow = 5;
      const front = Math.min(0.3, len * 0.45);
      const slot = (i, n, base, back) => {   // ranks of up to 5, extra ranks stepping back
        const row = Math.floor(i / perRow), inRow = Math.min(perRow, n - row * perRow), col = i % perRow;
        return base.clone().addScaledVector(side, (col - (inRow - 1) / 2) * gap).addScaledVector(back, row * gap);
      };
      const make = (f, n, base, back, faceDir) => {
        const shown = Math.min(CAP, n), list = [];
        for(let i = 0; i < shown; i++){
          const m = this.troop(f), at = slot(i, shown, base, back);
          m.userData.slot = at; if(m.userData.face) m.userData.face(faceDir.x, faceDir.z); list.push(m);
        }
        return { list, total: n, shown };
      };
      const aBase = B.clone().addScaledVector(dir, -front), dBase = B.clone().addScaledVector(dir, -front + 0.16);
      const att = make(attF, attN, aBase, dir.clone().negate(), dir), def = make(defF, defN, dBase, dir, dir.clone().negate());
      // defenders rise up in their ranks, attackers run in from their zone
      def.list.forEach(m => { m.position.copy(m.userData.slot); m.position.y = 0; m.scale.setScalar(0.01); m.userData.play('Ready1H'); });
      att.list.forEach(m => { m.position.copy(A); m.position.y = 0; m.userData.play('Run'); });
      this.animate(500, t => def.list.forEach(m => m.scale.setScalar(Math.max(0.01, easeOut(t)))));
      await this.animate(1000, t => att.list.forEach((m, i) => {
        const tt = Math.max(0, Math.min(1, t * 1.25 - i * 0.025)), e2 = ease(tt);
        m.position.lerpVectors(A, m.userData.slot, e2); m.position.y = 0;
      }));
      att.list.forEach(m => m.userData.play('Ready1H'));
      const fall = m => {
        if(m.userData.dead) return; m.userData.dead = true;
        const ms = m.userData.play('Death', true) || 600;
        setTimeout(() => this.animate(500, t => { m.position.y = -0.06 * t; m.scale.setScalar(Math.max(0.01, 1 - t * 0.6)); })
          .then(() => this.removeAll([m])), Math.min(ms, 1600) / this.speed);
      };
      const cullSide = (s, alive) => {
        const want = alive <= 0 ? 0 : Math.max(1, Math.ceil(alive / s.total * s.shown));
        const up = s.list.filter(m => !m.userData.dead);
        up.slice(0, Math.max(0, up.length - want)).forEach(fall);   // the front rank falls first
      };
      return {
        att: att.list, def: def.list,
        cull: (aAlive, dAlive) => { cullSide(att, aAlive); cullSide(def, dAlive); },
        finish: async captured => {
          const aUp = att.list.filter(m => !m.userData.dead), dUp = def.list.filter(m => !m.userData.dead);
          // winners give a battle roar, then everyone still standing leaves the field
          (captured ? aUp : dUp).forEach(m => m.userData.play('BattleRoar', true));
          await this.wait(450);
          const dest = captured ? B : A;
          aUp.forEach(m => { m.userData.play('Run'); if(m.userData.face){ const d = dest.clone().sub(m.position); m.userData.face(d.x, d.z); } });
          const from = aUp.map(m => m.position.clone());
          await Promise.all([
            this.animate(800, t => aUp.forEach((m, i) => { m.position.lerpVectors(from[i], dest, ease(t)); m.scale.setScalar(Math.max(0.01, 1 - Math.max(0, t - 0.6) / 0.4)); })),
            this.animate(600, t => dUp.forEach(m => m.scale.setScalar(Math.max(0.01, 1 - t))))
          ]);
          setTimeout(() => this.removeAll(att.list.concat(def.list)), 1700 / this.speed);   // after the last falls finish
        }
      };
    }
    removeAll(objs){ objs.forEach(o => { this.scene.remove(o); if(o.userData.mixer) this.mixers = this.mixers.filter(m => m !== o.userData.mixer); }); }

    // ----- playing log entries -----
    // Applies an entry's "after" zone snapshots once its animation reaches that point.
    applyAfter(entry){
      if(!entry.zones) return;
      Object.keys(entry.zones).forEach(k => { this.state.zones[k] = JSON.parse(JSON.stringify(entry.zones[k].after)); this.syncPiece(k); });
      this.drawMap();
    }
    async play(entry, opts){
      opts = opts || {};
      const fast = opts.instant || this.speed >= 8;
      if(fast){ this.applyAfter(entry); return; }
      const f = entry.faction;
      switch(entry.type){
        case 'deploy': return this.playDeploy(entry);
        case 'move': return this.playMove(entry);
        case 'attack': return this.playAttack(entry);
        case 'fortify': return this.playFortify(entry);
        case 'shieldwall': this.applyAfter(entry); this.floatText(entry.to, '🛡 Shield Wall', f); return this.pulseRing(entry.to, 0x9fd0ff);
        case 'build': return this.playBuild(entry);
        case 'autopilot': {
          this.applyAfter(entry);
          Object.keys(entry.placed).forEach(k => { this.floatText(k, `+${entry.placed[k]} (autopilot)`, f); this.pulseRing(k, 0xaaaaaa); });
          return this.wait(700);
        }
        case 'dawn': return this.playDawn(entry);
        case 'start': this.applyAfter(entry); return this.overview(1200);
        case 'pet': {   // a pet joining or moving: fly to it and mark the spot (the pet itself settles with the board)
          await this.focusZones(entry.from ? [entry.from, entry.to] : [entry.to], 700, 4.6);
          this.floatText(entry.to, entry.from ? '🐾 moved here' : '🐾 joins the war', f); this.pulseRing(entry.to, 0xffd36a);
          return this.wait(900);
        }
        case 'craft': case 'trade': case 'join': return this.wait(1100);   // nothing moves on the map: the caption says what happened
        default: this.applyAfter(entry); return;
      }
    }
    async playDeploy(e){
      await this.focusZones([e.to], 700, 4.2);
      const at = zoneWorld(e.to), toks = [];
      const n = Math.min(5, e.n);
      for(let i = 0; i < n; i++){
        const m = this.troop(e.faction);
        m.position.set(at.x + (i % 3 - 1) * 0.09, 2, at.z + 0.14 + Math.floor(i / 3) * 0.09);
        if(m.userData.face) m.userData.face(0, 1);   // facing the camera side of the table
        toks.push(m);
      }
      await this.animate(700, t => toks.forEach((m, i) => {
        const tt = Math.max(0, Math.min(1, t * 1.4 - i * 0.07)); const b = tt < 1 ? 1 - easeOut(tt) : 0;
        m.position.y = b * 2 + (tt > 0.85 ? Math.sin((tt - 0.85) / 0.15 * Math.PI) * 0.03 : 0);
      }));
      const roar = Math.max(...toks.map(m => m.userData.play('BattleRoar', true) || 0));
      this.pulseRing(e.to, COL[e.faction + 'Hex']);
      this.applyAfter(e); this.floatText(e.to, `+${e.n} ⚔`, e.faction);
      await this.wait(Math.max(350, Math.min(1600, roar)));
      await this.animate(300, t => toks.forEach(m => { m.scale.setScalar(1 - t); })); this.removeAll(toks);
    }
    async playMove(e){
      await this.focusZones([e.from, e.to], 700);
      const curve = this.arcCurve(e.from, e.to, 0.12);
      const toks = await this.marchTokens(curve, e.n, e.faction, 1100);
      this.applyAfter(e); this.floatText(e.to, `+${e.n} 💤`, e.faction);
      await this.animate(250, t => toks.forEach(m => m.scale.setScalar(1 - t))); this.removeAll(toks);
    }
    async playFortify(e){
      await this.focusZones([e.to], 700, 3.6);
      this.applyAfter(e);
      const w = this.pieces[e.to].fort || this.pieces[e.to].wall;
      if(this.pieces[e.to].fort){
        // wall models grow up out of the board, then rest exactly at their size on it
        const base = w.scale.clone();
        await this.animate(700, t => { w.scale.set(base.x, base.y * Math.max(0.01, easeOut(t)), base.z); });
        w.scale.copy(base);
      } else {
        await this.animate(700, t => { w.children.forEach((s, i) => { const tt = Math.max(0, Math.min(1, t * 1.6 - i * 0.04)); s.position.y = -0.04 + easeOut(tt) * 0.07; }); });
        w.children.forEach(s => { s.position.y = 0.03; });
      }
      this.pulseRing(e.to, 0xd8c8a0); this.floatText(e.to, '🧱 Fortified', e.faction);
      await this.wait(500);
    }
    async playBuild(e){
      await this.focusZones([e.to], 700, 3.6);
      this.applyAfter(e);
      const obj = e.kind === 'stronghold' ? (this.pieces[e.to].hold || this.pieces[e.to].tower) : (this.pieces[e.to].post || this.pieces[e.to].tent);
      const base = obj.scale.clone();
      await this.animate(800, t => { obj.scale.set(base.x, base.y * Math.max(0.01, easeOut(t)), base.z); });
      obj.scale.copy(base);
      this.pulseRing(e.to, 0xffd36a); this.floatText(e.to, e.kind === 'stronghold' ? '🏰 Stronghold' : '⛺ Outpost', e.faction);
      await this.wait(500);
    }
    async playDawn(e){
      // a sweep of morning light over the table, fresh troops stand up
      const k = this.keyLight, base = k.intensity;
      await this.animate(1200, t => { k.intensity = base + Math.sin(t * Math.PI) * 1.2; k.color.setRGB(1, 0.86 + 0.1 * Math.sin(t * Math.PI), 0.7); });
      k.intensity = base; k.color.setHex(0xffe2b0);
      this.applyAfter(e);
    }
    async playAttack(e){
      const att = e.faction, def = e.defender;
      await this.focusZones([e.from, e.to], 800);
      const curve = this.arcCurve(e.from, e.to);
      const arrow = this.drawArrow(curve, att === 'horde' ? 0xff4a30 : 0x5a9aff);
      await arrow.grow;
      const A = zoneWorld(e.from), B = zoneWorld(e.to);
      const mid = A.clone().lerp(B, 0.62);
      // both armies on the board: the attackers march up and form ranks facing the defenders, who form up in
      // front of their zone. One figure per troop (up to 10 a side, then each stands for a few); as troops die,
      // figures fall and vanish
      const defStart = e.zones[e.to].before.ready + e.zones[e.to].before.fresh;
      const armies = await this.formArmies(A, B, e.n, defStart, att, def === 'neutral' ? 'neutral:' + WAR_ZONES[e.to].region : def);
      const toks = armies.att;
      toks.forEach(m => m.userData.play('Attack1H')); armies.def.forEach(m => m.userData.play('Attack1H'));
      if(e.naval) this.floatText(e.to, '⛵ Naval Landing', att);
      if(e.warcry) this.floatText(e.from, '📯 Warcry!', att);
      if(e.fortified) this.floatText(e.to, '🧱 Fortified +1', def);
      // show up to 3 rounds rolled out, the rest summarised
      const shown = e.rounds.slice(0, 3);
      let attLeft = e.n, defLeft = e.zones[e.to].before.ready + e.zones[e.to].before.fresh;
      for(let i = 0; i < shown.length; i++){
        const r = shown[i];
        this.clearDice();
        await Promise.all([
          this.throwDice(r.ad, att, A, mid.clone().add(new THREE.Vector3(0, 0, -0.18)), 900),
          this.throwDice(r.dd, def === 'neutral' ? 'neutral' : def, B, mid.clone().add(new THREE.Vector3(0, 0, 0.18)), 950)
        ]);
        const attDice = this.dice.slice(0, r.ad.length), defDice = this.dice.slice(r.ad.length);
        await this.judgeDice(attDice, defDice, r.bonus || 0);
        await this.flash(mid, 0xffc070, 1.2);
        this.shake(260, 0.08);
        attLeft -= r.al; defLeft -= r.dl;
        if(r.al) this.floatText(e.from, `-${r.al}`, 'loss');
        if(r.dl) this.floatText(e.to, `-${r.dl}`, 'loss');
        armies.cull(Math.max(0, attLeft), Math.max(0, defLeft));
        await this.wait(650);
      }
      this.clearDice();
      if(e.rounds.length > 3){
        const rest = e.rounds.slice(3); let al = 0, dl = 0; rest.forEach(r => { al += r.al; dl += r.dl; });
        this.floatText(e.to, `${rest.length} more round${rest.length > 1 ? 's' : ''}: -${al} / -${dl}`, 'sum');
        // the rest of the fight plays out quickly: figures keep falling round by round
        const steps = Math.min(6, rest.length), per = Math.ceil(rest.length / steps);
        for(let i = 0; i < steps; i++){
          rest.slice(i * per, (i + 1) * per).forEach(r => { attLeft -= r.al; defLeft -= r.dl; });
          this.flash(mid.clone().add(new THREE.Vector3((Math.random() - 0.5) * 0.4, 0, (Math.random() - 0.5) * 0.3)), 0xff9a50, 0.8); this.shake(160, 0.05);
          armies.cull(Math.max(0, attLeft), Math.max(0, defLeft));
          await this.wait(420);
        }
      }
      armies.cull(e.captured ? Math.max(0, e.survivors) : Math.max(0, attLeft), e.captured ? 0 : Math.max(0, defLeft));
      await this.wait(450);
      // the zone changes hands as the survivors march in, not after they've gone
      const leaving = armies.finish(e.captured);
      if(!e.captured) await leaving;
      arrow.remove();
      if(e.captured){
        const fx = this.captureFx(e.to, att);
        await this.wait(250);
        this.applyAfter(e);
        const fl = this.pieces[e.to].flagModel || this.pieces[e.to].flag;
        const base = fl.scale.clone();   // the banner models carry a small scale of their own: fold relative to it
        await this.animate(600, t => { fl.scale.set(base.x, base.y * Math.max(0.05, 1 - Math.sin(t * Math.PI) * 0.95), base.z); });
        fl.scale.copy(base);
        this.floatText(e.to, '⚑ Captured!', att);
        await fx;
      } else {
        this.applyAfter(e);
        this.floatText(e.to, '🛡 Held!', def);
      }
      await this.wait(700);
    }

    // ----- input -----
    pickZone(clientX, clientY){
      const r = this.renderer.domElement.getBoundingClientRect();
      this.mouse.set(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
      this.raycaster.setFromCamera(this.mouse, this.camera);
      const hit = this.raycaster.intersectObject(this.mapMesh)[0];
      if(!hit || !hit.uv) return null;
      if(!this.raster) return null;
      const RW = this.RW, RH = this.RH, px = Math.floor(hit.uv.x * RW), py = Math.floor((1 - hit.uv.y) * RH);
      const z = this.raster[Math.max(0, Math.min(RH - 1, py)) * RW + Math.max(0, Math.min(RW - 1, px))];
      return isZone(z) ? WAR_ZONE_ORDER[z - 1] : null;
    }
    bindInput(){
      const el = this.renderer.domElement;
      // the board takes every touch itself: without this a phone treats a drag as a page scroll/zoom and cancels
      // the pointer after a few pixels, so the camera only twitched
      el.style.touchAction = 'none'; el.style.webkitUserSelect = el.style.userSelect = 'none'; el.style.webkitTouchCallout = 'none';
      let drag = null; const pts = new Map();
      el.addEventListener('contextmenu', e => e.preventDefault());
      el.addEventListener('pointerleave', () => { if(this.hoverRegion){ this.hoverRegion = null; this.drawMap(); } });
      el.addEventListener('pointerdown', e => {
        el.setPointerCapture(e.pointerId); pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
        drag = { x: e.clientX, y: e.clientY, moved: 0, btn: e.button, pinch: pts.size === 2 ? this.pinchDist(pts) : 0 };
      });
      el.addEventListener('pointermove', e => {
        if(!drag){
          const k = this.pickZone(e.clientX, e.clientY);
          el.style.cursor = k ? 'pointer' : 'grab';
          if(this.opts.onHover) this.opts.onHover(k, e);
          const reg = k ? WAR_ZONES[k].region : null;
          if(reg !== this.hoverRegion){ this.hoverRegion = reg; this.drawMap(); }
          return;
        }
        const prev = pts.get(e.pointerId); if(!prev) return;
        const dx = e.clientX - prev.x, dy = e.clientY - prev.y; pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
        drag.moved += Math.abs(dx) + Math.abs(dy);
        if(pts.size === 2){
          const d = this.pinchDist(pts); if(drag.pinch){ this.cam.dist = Math.max(2.2, Math.min(16, this.cam.dist * drag.pinch / d)); } drag.pinch = d; return;
        }
        if(drag.btn === 2 || e.shiftKey){
          this.cam.az -= dx * 0.005; this.cam.polar = Math.max(0.15, Math.min(1.3, this.cam.polar - dy * 0.004));
        } else {
          const s = this.cam.dist * 0.0016, ca = Math.cos(this.cam.az), sa = Math.sin(this.cam.az);
          this.cam.target.x -= (dx * ca + dy * sa) * s; this.cam.target.z -= (-dx * sa + dy * ca) * s;
          this.cam.target.x = Math.max(-PW / 2, Math.min(PW / 2, this.cam.target.x)); this.cam.target.z = Math.max(-PH / 2, Math.min(PH / 2, this.cam.target.z));
        }
      });
      const up = e => {
        pts.delete(e.pointerId);
        if(drag && drag.moved < 6 && pts.size === 0){
          if(this.smashMode && this.opts.onSmash){ this.opts.onSmash(e.clientX, e.clientY); pts.clear(); drag = null; return; }
          if(this.eggs && this.eggs.length){
            const r = this.renderer.domElement.getBoundingClientRect();
            this.mouse.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
            this.raycaster.setFromCamera(this.mouse, this.camera);
            const blockers = [this.table, this.mapMesh].filter(Boolean), hit = this.raycaster.intersectObjects(this.eggs.map(g => g.obj).concat(blockers), true)[0];
            if(hit){ const egg = this.eggs.find(g => { for(let q = hit.object; q; q = q.parent) if(q === g.obj) return true; return false; }); if(egg){ egg.fn(); pts.clear(); drag = null; return; } }
          }
          if(this.doorModel && this.toggleDoor){
            const r = this.renderer.domElement.getBoundingClientRect();
            this.mouse.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
            this.raycaster.setFromCamera(this.mouse, this.camera);
            if(this.raycaster.intersectObjects(this.doorHits || [this.doorModel], true).length){ this.toggleDoor(); pts.clear(); drag = null; return; }
          }
          if(this.opts.onClick) this.opts.onClick(this.pickZone(e.clientX, e.clientY), e);
        }
        if(pts.size === 0) drag = null;
      };
      el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
      el.addEventListener('wheel', e => { e.preventDefault(); this.cam.dist = Math.max(2.2, Math.min(16, this.cam.dist * (e.deltaY > 0 ? 1.1 : 0.9))); }, { passive: false });
    }
    pinchDist(pts){ const [a, b] = [...pts.values()]; return Math.hypot(a.x - b.x, a.y - b.y) || 1; }
    resize(){
      const w = this.el.clientWidth, h = this.el.clientHeight;
      this.renderer.setSize(w, h); this.camera.aspect = w / h;
      // keep at least the desktop's sideways view on a tall phone screen: widen the vertical angle instead of
      // backing the camera out of the room
      const HFOV = 2 * Math.atan(Math.tan(42 / 2 * Math.PI / 180) * 1.6);
      this.camera.fov = Math.min(80, Math.max(42, 2 * Math.atan(Math.tan(HFOV / 2) / this.camera.aspect) * 180 / Math.PI));
      this.camera.updateProjectionMatrix();
    }

    // ----- frame -----
    tick(){
      const now = performance.now();
      const dt = Math.min(0.1, (now - (this._last || now)) / 1000); this._last = now;
      (this.mixers || []).forEach(m => m.update(dt));
      this.tickEggs(now);
      if(this.debris){ this.smashAcc = Math.min(0.25, (this.smashAcc || 0) + dt); while(this.smashAcc >= 1 / 60){ this.smashStep(1 / 60); this.smashAcc -= 1 / 60; } }
      if(this.water){ this.water.offset.x = now / 90000; this.water.offset.y = Math.sin(now / 7000) * 0.03; }
      // tweens can start new tweens (a die landing throws sparks): run this frame's batch, then keep anything
      // added meanwhile, or the new ones would be dropped and their effects left frozen on the board
      const batch = this.anims; this.anims = [];
      const live = batch.filter(a => {
        const t = Math.min(1, (now - a.t0) / a.ms); a.fn(t);
        if(t >= 1){ a.res(); return false; } return true;
      });
      this.anims = live.concat(this.anims);
      this.applyCamera();
      // flags wave, rings breathe
      KEYS.forEach(k => {
        const p = this.pieces[k], pos = p.flagGeo.attributes.position, b = p.base;
        for(let i = 0; i < pos.count; i++){ const x = b[i * 3] + 0.1; pos.array[i * 3 + 2] = Math.sin(now / 260 + x * 30 + p.seed) * 0.018 * x * 8; }
        pos.needsUpdate = true;
                p.ring.visible = false;
      });
      this.flames.forEach(f => {
        const k = 0.8 + 0.12 * Math.sin(now / 90 + f.seed) + 0.08 * Math.sin(now / 37 + f.seed * 3);
        f.l.intensity = f.base * k; f.f.scale.y = (f.s === 1 ? 0.3 : 2.2) * (0.9 + 0.15 * k);
      });
      if(this.selGlow){ this.selGlow.material.opacity = 0.85 + 0.15 * Math.sin(now / 600); this.tgtGlow.material.opacity = 0.45 + 0.4 * Math.sin(now / 260); }
      this.moveVehicles(now, dt);
      if(this.snowfall){
        const a = this.snowfall.geometry.attributes.position, d = this.snowDoor;
        for(let i = 0; i < a.count; i++){
          // wind: a steady push sideways with gusts that come and go, plus each flake's own flutter
          const gust = 0.9 + 0.8 * Math.sin(now / 2300) + 0.5 * Math.sin(now / 870 + 1.3);
          let y = a.getY(i) - dt * (0.45 + (i % 7) * 0.07);
          let x = a.getX(i) + dt * (1.1 * gust + Math.sin(now / 300 + i * 1.7) * 0.5);
          if(y < 0) y += d.h;
          if(x > d.w / 2) x -= d.w;   // blown off one side, back in the other
          a.setY(i, y); a.setX(i, x);
        }
        a.needsUpdate = true;
      }
      this.renderer.render(this.scene, this.camera);
      // overlay labels follow their zones
      const w = this.el.clientWidth, h = this.el.clientHeight, v = new THREE.Vector3();
      KEYS.forEach(k => {
        const p = this.pieces[k]; if(!p.grp.visible) return;
        v.copy(p.grp.position); v.y = 0.36 * (p.fit || 1); v.project(this.camera);   // just above the banner's top, scaled with the zone's pieces
        p.lab.style.transform = `translate(-50%,-100%) translate(${(v.x + 1) / 2 * w}px,${(1 - v.y) / 2 * h}px)`;
        p.lab.style.opacity = v.z < 1 ? '' : '0';
        const close = this.cam.dist < 13;
        const small = (this.camera.aspect || 1.5) < 0.8 ? 0.8 : 1;   // phones: smaller plates over the smaller map
        p.lab.style.fontSize = Math.round((close ? Math.max(10, Math.min(15, 120 / this.cam.dist)) : 9) * small) + 'px';
      });
      (this.floats || []).forEach(f => {
        const t = (now - f.t0) / (1800 / this.speed);
        v.copy(f.p); v.y += t * 0.5; v.project(this.camera);
        f.el.style.transform = `translate(-50%,-50%) translate(${(v.x + 1) / 2 * w}px,${(1 - v.y) / 2 * h}px)`;
        f.el.style.opacity = String(Math.max(0, 1 - Math.max(0, t - 0.6) / 0.4));
      });
    }
  }
  window.WarBoard = WarBoard;
})();
