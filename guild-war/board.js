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
  function dieFaceTex(n, bg, pip){
    return canvasTex(128, 128, (g) => {
      g.fillStyle = bg; g.fillRect(0, 0, 128, 128);
      g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 6; g.strokeRect(3, 3, 122, 122);
      g.fillStyle = pip;
      const P = { 1: [[64, 64]], 2: [[34, 34], [94, 94]], 3: [[30, 30], [64, 64], [98, 98]], 4: [[34, 34], [94, 34], [34, 94], [94, 94]],
                  5: [[32, 32], [96, 32], [64, 64], [32, 96], [96, 96]], 6: [[34, 28], [94, 28], [34, 64], [94, 64], [34, 100], [94, 100]] }[n];
      P.forEach(([x, y]) => { g.beginPath(); g.arc(x, y, 11, 0, Math.PI * 2); g.fill(); });
    });
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
      this.cam = { target: new THREE.Vector3(0, 0, 0.3), dist: 11.5, polar: 0.62, az: 0 }; this.shakeOff = new THREE.Vector3();
      this.glow = glowTex();
      this.buildRoom(); this.loadTable(); this.loadStrongholds(); this.loadFlags(); this.loadScenery(); this.loadTerrainModels(); this.loadSnowman(); this.loadDoorway(); this.loadSuccubus(); this.loadPainting(); this.loadShips(); this.buildMap(); this.buildDice();
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
      const R2W = window.WAR_TEX_BASE || 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/War%20Games/';
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
          const DT = 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/War%20Games/War%20Room/Door/';
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
        c.position.set(x, y + 0.2 * s, z); c.castShadow = true; S.add(c);
        const f = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glow, color: 0xffb04a, blending: THREE.AdditiveBlending, depthWrite: false }));
        f.position.set(x, y + 0.48 * s, z); f.scale.set(0.22 * s, 0.4 * s, 1); S.add(f);
        const l = new THREE.PointLight(0xff9a3c, 0.5, 5 * s, 2); l.position.set(x, y + 0.6 * s, z); S.add(l);
        this.flames.push({ f, l, s, seed: Math.random() * 100, base: 0.5 });
      };
      [[-5.55, -3.55], [5.55, -3.55], [-5.55, 3.55], [5.55, 3.55]].forEach(([x, z]) => candle(x, 0.17, z, 1));
      // floating dust in the light
      const n = 260, pos = new Float32Array(n * 3);
      for(let i = 0; i < n; i++){ pos[i * 3] = (Math.random() - 0.5) * 14; pos[i * 3 + 1] = Math.random() * 8; pos[i * 3 + 2] = (Math.random() - 0.5) * 10; }
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      this.dust = new THREE.Points(g, new THREE.PointsMaterial({ map: this.glow, color: 0xffd9a0, size: 0.06, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false }));
      S.add(this.dust);
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
        alliance: { url: 'models/war/alliance-stronghold.gltf', drop: /cellar|war_room|armordealer|weapondealer|generalarea/i, mask: /windows_01/i, size: 0.5, rotY: -Math.PI / 2 }
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
          grp.position.set(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
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
        let cur = mixer.clipAction(clip('Opened')); cur.play();
        this.doorOpen = true; this.doorModel = m;
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

    // ----- ships on the sea, moored along the boat routes: Booty Bay pirate ships and Alliance transports.
    // Each sits a few steps out along a route's sea path from the named zone. -----
    loadShips(){
      if(!THREE.GLTFLoader) return;
      const M = window.WAR_SHIPS || { pirate: 'models/war/pirate-ship.gltf', alliance: 'models/war/alliance-ship.gltf' };
      const SHIPS = [
        { kind: 'pirate',   route: 'tanaris|riverglades',    from: 'tanaris' },
        { kind: 'pirate',   route: 'barrens|stranglethorn',  from: 'barrens' },
        { kind: 'pirate',   route: 'tanaris|riverglades',    from: 'riverglades' },
        { kind: 'alliance', route: 'elwynn|darkshore',       from: 'elwynn' },
        { kind: 'alliance', route: 'darkshore|wetlands',     from: 'wetlands' },
        { kind: 'alliance', route: 'dustwallow|wetlands',    from: 'dustwallow', step: 1 },   // in close to Theramore
        { kind: 'alliance', route: 'darkshore|wetlands',     from: 'darkshore' }
      ];
      const protos = {};
      const place = () => {
        if(!this.raster) return setTimeout(place, 300);
        const paths = this.seaPaths = this.seaPaths || this.routeSeaPaths();
        SHIPS.forEach((sh, i) => {
          const proto = protos[sh.kind], path = paths[sh.route]; if(!proto || !path) return;
          const fromStart = sh.route.split('|')[0] === sh.from;
          const seq = fromStart ? path : path.slice().reverse();
          const st = sh.step != null ? sh.step : sh.from === 'wetlands' ? 2 : 3;
          const at = seq[Math.min(seq.length - 1, st)], next = seq[Math.min(seq.length - 1, st + 2)];
          const w = toWorld(at[0], at[1]), w2 = toWorld(next[0], next[1]);
          const ship = proto.clone(); ship.position.set(w.x, this.sheetY(at[0], at[1]) + 0.004, w.z);
          ship.rotation.y = Math.atan2(-(w2.z - w.z), w2.x - w.x) + (i % 2 ? 0.25 : -0.25);   // bow (+x) along the route
          ship.userData.bob = Math.random() * 6; this.scene.add(ship); (this.ships = this.ships || []).push(ship);
        });
      };
      let left = 2;
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
        const box = new THREE.Box3().setFromObject(grp), s = 0.52 / (box.max.x - box.min.x);   // ~0.52 units long
        grp.position.set(-(box.min.x + box.max.x) / 2, 0, -(box.min.z + box.max.z) / 2);      // origin stays at the waterline
        const holder = new THREE.Group(), inner = new THREE.Group(); inner.add(grp); inner.scale.setScalar(s); holder.add(inner);
        protos[kind] = holder;
        if(--left === 0) place();
      }, undefined, err => { console.warn(kind + ' ship failed to load:', err); if(--left === 0) place(); }));
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
      const R2 = 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/';
      this.resIcons = {};
      Object.entries({ food: 'FoodIcon.png', wood: 'WoodIcon.png', ore: 'War%20Games/CopperOre.png', crystal: 'CrystalIcon2.png' }).forEach(([r, f]) => {
        const im = new Image(); im.crossOrigin = 'anonymous';
        im.onload = () => { this.resIcons[r] = im; this.drawMap(); };
        im.src = R2 + f;
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
        this.drawMap(); this.buildTerrain();
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
      this.drawMap();
    }
    // Boat routes: shortest sea path (A* on a coarse grid of the outline map) from the coast nearest one
    // zone's anchor to the coast nearest the other's, kept a little off the shore, then thinned to waypoints.
    // harbours: where boat lines land for a zone (map px); others land on the coast nearest the zone's banner
    routeSeaPaths(){
      const HARBOURS = { wetlands: [918, 624] };   // Menethil Harbor, on the west coast
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
      const cost = i => 1 + 8 * Math.exp(-dist[i] / 2.5);
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
            const j = ny * GW + nx; if(!sea[j]) continue;
            const ng = g[i] + cost(j) * (dx && dy ? 1.414 : 1);
            if(ng < g[j]){ g[j] = ng; from[j] = i; push([ng + hz(j), j]); }
          }
        }
        if(from[t] < 0 && s !== t) return null;
        const out = []; for(let i = t; i >= 0; i = from[i]){ out.push(i); if(i === s) break; }
        return out.reverse();
      };
      const paths = {};
      WAR_ROUTES.filter(rt => rt.kind === 'boat').forEach(rt => {
        const A = WAR_LAYOUT[rt.a], B = WAR_LAYOUT[rt.b];
        const pa = HARBOURS[rt.a] || [A.x, A.y], pb = HARBOURS[rt.b] || [B.x, B.y];
        const s = nearestSea(pa[0], pa[1], HARBOURS[rt.a] ? toG(...pa) : toG(B.x, B.y)), t = nearestSea(pb[0], pb[1], HARBOURS[rt.b] ? toG(...pb) : toG(A.x, A.y));
        if(s < 0 || t < 0) return;
        const cells = astar(s, t); if(!cells) return;
        const pts = cells.filter((_, i) => i % 6 === 0 || i === cells.length - 1)
          .map(i => [((i % GW) + 0.5) * S / RW * MW, ((((i / GW) | 0) + 0.5) * S) / RH * MH]);
        // run the line right into the harbour
        if(HARBOURS[rt.a]) pts.unshift(HARBOURS[rt.a]);
        if(HARBOURS[rt.b]) pts.push(HARBOURS[rt.b]);
        paths[rt.a + '|' + rt.b] = pts;
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
        const own = new Array(256).fill(null);
        WAR_ZONE_ORDER.forEach((k, i) => { own[i + 1] = this.ownerOf(k); });
        const sel = this.selected ? this.zoneVal[this.selected] : -1;
        const hl = new Set((this.highlights || []).map(k => this.zoneVal[k]));
        for(let y = 0; y < RH; y++) for(let x = 0; x < RW; x++){
          const i = y * RW + x, z = R[i], o = i * 4;
          if(!isZone(z)) continue;
          const r = x + 1 < RW ? R[i + 1] : z, b = y + 1 < RH ? R[i + RW] : z, l = x > 0 ? R[i - 1] : z, t = y > 0 ? R[i - RW] : z;
          const border = (isZone(r) && r !== z) || (isZone(b) && b !== z) || (isZone(l) && l !== z) || (isZone(t) && t !== z);
          if(border){ d[o] = 40; d[o + 1] = 24; d[o + 2] = 10; d[o + 3] = 200; continue; }
          const c = COL[own[z]] || COL.neutral;
          let a = own[z] === 'neutral' ? 0 : 0.36, cr = c[0], cg = c[1], cb = c[2];
          if(z === sel){ cr = 255; cg = 230; cb = 150; a += 0.3; }
          else if(hl.has(z)){ cr = 255; cg = 210; cb = 120; a += 0.2; }
          d[o] = cr; d[o + 1] = cg; d[o + 2] = cb; d[o + 3] = Math.round(Math.min(1, a) * 255);
        }
        oc.putImageData(im, 0, 0);
        g.imageSmoothingEnabled = true;
        g.drawImage(this.overlayCanvas, 0, 0, W, H);
      }
      // routes: boats follow the sea around the coasts; zeppelins fly straight over
      const seaPaths = this.raster ? (this.seaPaths = this.seaPaths || this.routeSeaPaths()) : {};
      WAR_ROUTES.forEach(rt => {
        const path = rt.kind === 'boat' && seaPaths[rt.a + '|' + rt.b];
        if(path){
          g.setLineDash([20, 13]); g.lineWidth = 5; g.strokeStyle = 'rgba(24,48,70,0.7)';
          g.beginPath(); g.moveTo(path[0][0] * sx, path[0][1] * sy);
          for(let i = 1; i < path.length - 1; i++){
            const mx = (path[i][0] + path[i + 1][0]) / 2, my = (path[i][1] + path[i + 1][1]) / 2;
            g.quadraticCurveTo(path[i][0] * sx, path[i][1] * sy, mx * sx, my * sy);
          }
          const last = path[path.length - 1]; g.lineTo(last[0] * sx, last[1] * sy); g.stroke(); g.setLineDash([]);
          return;
        }
        const a = WAR_LAYOUT[rt.a], b = WAR_LAYOUT[rt.b];
        const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, dx = b.x - a.x, dy = b.y - a.y;
        const bend = rt.kind === 'zeppelin' ? -0.18 : 0.14;
        const cx = mx - dy * bend, cy = my + dx * bend;
        g.setLineDash(rt.kind === 'zeppelin' ? [8, 16] : [20, 13]); g.lineWidth = rt.kind === 'zeppelin' ? 4 : 5;
        g.strokeStyle = rt.kind === 'zeppelin' ? 'rgba(92,52,20,0.75)' : 'rgba(24,48,70,0.7)';
        g.beginPath(); g.moveTo(a.x * sx, a.y * sy); g.quadraticCurveTo(cx * sx, cy * sy, b.x * sx, b.y * sy); g.stroke();
        g.setLineDash([]);
      });
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
      const path = pts => { g.beginPath(); g.moveTo(pts[0][0], pts[0][1]); pts.slice(1).forEach(p => g.lineTo(p[0], p[1])); g.closePath(); };
      g.save();
      g.lineJoin = 'round';
      g.strokeStyle = 'rgba(30,18,6,0.55)'; g.lineWidth = 16; tears.forEach(p => { path(p); g.stroke(); });   // shadow of the curled lip
      g.strokeStyle = 'rgba(236,224,196,0.95)'; g.lineWidth = 8; tears.forEach(p => { path(p); g.stroke(); });  // pale torn-paper fibres
      g.globalCompositeOperation = 'destination-out';
      tears.forEach(p => { path(p); g.fill(); });             // then the tear itself
      g.lineWidth = 3; g.strokeStyle = '#000';
      g.beginPath(); g.rect(0, 0, W, H); g.stroke();          // ragged-free hairline so the sheet edge is clean
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
      base.position.y = 0.015; grp.add(base);
      // stronghold tower / outpost tent (hidden until built)
      const towerMat = new THREE.MeshStandardMaterial({ color: 0x8a8070, roughness: 0.9 });
      const tower = new THREE.Group();
      const t1 = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.11, 0.28, 10), towerMat); t1.position.y = 0.14; t1.castShadow = true; tower.add(t1);
      const roof = new THREE.Mesh(new THREE.ConeGeometry(0.12, 0.14, 10), new THREE.MeshStandardMaterial({ color: COL.neutralHex })); roof.position.y = 0.35; roof.castShadow = true; tower.add(roof);
      tower.position.set(-0.17, 0, 0.04); grp.add(tower);
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
          p.hold = model.clone(); p.hold.position.set(-0.2, 0.002, -0.06);
          const th = TUNE.holds[k]; if(th){ if(th.rot) p.hold.rotation.y = th.rot; if(th.scale) p.hold.scale.setScalar(th.scale); }
          p.grp.add(p.hold);
        }
        p.holdFor = model ? z.owner : null;
      }
      p.tower.visible = z.outpost >= 2 && !model; p.tent.visible = z.outpost === 1;
      const now = this.state ? this.state.clock : 0;
      p.wall.visible = z.fortifyUntil > now;
      const info = WAR_ZONES[k];
      p.lab.className = 'wb-label ' + z.owner + (this.selected === k ? ' sel' : '');
      p.lab.innerHTML = `<b>${z.ready}</b>⚔${z.fresh ? `<i>+${z.fresh}💤</i>` : ''}${info.capital ? '<s>♛</s>' : ''}${z.shield ? '<s>🛡</s>' : ''}`;
      p.lab.title = `${info.name}: ${z.ready} ready, ${z.fresh} fresh`;
    }
    select(k, targets){
      this.selected = k; this.highlights = targets || [];
      KEYS.forEach(z => this.syncPiece(z));
      this.drawMap();
    }

    // ----- dice -----
    buildDice(){
      const mk = (bg, pip) => [1, 6, 2, 5, 3, 4].map(n => new THREE.MeshStandardMaterial({ map: dieFaceTex(n, bg, pip), roughness: 0.4 }));
      this.dieMats = { horde: mk('#b3221c', '#f4e6c8'), alliance: mk('#2454be', '#f4e6c8'), neutral: mk('#e8dcc0', '#2a1a0c') };
      this.dieGeo = new THREE.BoxGeometry(0.16, 0.16, 0.16);
      this.dice = [];
    }
    faceQuat(v){
      const e = { 1: [0, 0, Math.PI / 2], 6: [0, 0, -Math.PI / 2], 2: [0, 0, 0], 5: [Math.PI, 0, 0], 3: [-Math.PI / 2, 0, 0], 4: [Math.PI / 2, 0, 0] }[v];
      return new THREE.Quaternion().setFromEuler(new THREE.Euler(e[0], e[1], e[2]));
    }
    clearDice(){ this.dice.forEach(d => this.scene.remove(d)); this.dice = []; }
    // Throw a set of dice from `from` toward `at`, landing showing `vals`
    throwDice(vals, faction, from, at, ms){
      const out = [];
      vals.forEach((v, i) => {
        const m = new THREE.Mesh(this.dieGeo, this.dieMats[faction] || this.dieMats.neutral); m.castShadow = true;
        const side = new THREE.Vector3(at.z - from.z, 0, from.x - at.x).normalize();
        const end = at.clone().add(side.clone().multiplyScalar((i - (vals.length - 1) / 2) * 0.22)); end.y = 0.08;
        const start = from.clone(); start.y = 0.9;
        const qEnd = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.random() * 6.28).multiply(this.faceQuat(v));
        const spin = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
        this.scene.add(m); this.dice.push(m);
        out.push(this.animate(ms, t => {
          const e = easeOut(t);
          m.position.lerpVectors(start, end, e);
          m.position.y = 0.08 + Math.sin(Math.min(1, t * 1.15) * Math.PI) * 0.7 * (1 - t) + Math.abs(Math.sin(t * Math.PI * 3)) * 0.12 * (1 - t);
          m.quaternion.copy(qEnd).premultiply(new THREE.Quaternion().setFromAxisAngle(spin, (1 - e) * 14));
        }));
      });
      return Promise.all(out);
    }

    // ----- generic tween helper (speed-aware) -----
    animate(ms, fn){
      return new Promise(res => { this.anims.push({ t0: performance.now(), ms: ms / this.speed, fn, res }); });
    }
    wait(ms){ return sleep(ms / this.speed); }

    // ----- camera -----
    applyCamera(){
      const c = this.cam, sp = Math.sin(c.polar);
      this.camera.position.set(c.target.x + c.dist * sp * Math.sin(c.az), c.target.y + c.dist * Math.cos(c.polar), c.target.z + c.dist * sp * Math.cos(c.az));
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
    async intro(){
      // stand in the doorway, then sweep down over the table
      this.cam = { target: new THREE.Vector3(0, 0.5, -2), dist: 17, polar: 1.32, az: 0.0 };
      this.applyCamera();
      await this.tweenCam({ target: new THREE.Vector3(0, 0, 0.3), dist: 11.5, polar: 0.62, az: 0 }, 3200);
    }
    focusZones(keys, ms, dist){
      const v = new THREE.Vector3(); keys.forEach(k => v.add(zoneWorld(k))); v.multiplyScalar(1 / keys.length);
      let spread = 0; keys.forEach(k => { spread = Math.max(spread, zoneWorld(k).distanceTo(v)); });
      return this.tweenCam({ target: v, dist: dist || Math.max(3.2, spread * 2.6 + 2.6), polar: 0.78 }, ms || 900);
    }
    overview(ms){ return this.tweenCam({ target: new THREE.Vector3(0, 0, 0.3), dist: 11.5, polar: 0.62, az: 0 }, ms || 900); }
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
    marchTokens(curve, n, faction, ms){
      const count = Math.min(6, Math.max(1, n));
      const mat = new THREE.MeshStandardMaterial({ color: COL[faction + 'Hex'] || COL.neutralHex, metalness: 0.3, roughness: 0.5 });
      const toks = [];
      for(let i = 0; i < count; i++){
        const m = new THREE.Group();
        const body = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 0.1, 8), mat); body.position.y = 0.05; m.add(body);
        const head = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 6), mat); head.position.y = 0.12; m.add(head);
        m.castShadow = true; this.scene.add(m); toks.push(m);
      }
      return this.animate(ms, t => {
        toks.forEach((m, i) => {
          const tt = Math.max(0, Math.min(1, t * 1.3 - i * 0.06));
          const p = curve.getPoint(ease(tt)); m.position.copy(p); m.position.y = Math.max(0.0, p.y - 0.06) + Math.abs(Math.sin(tt * 18 + i)) * 0.03;
          m.position.x += (i % 3 - 1) * 0.05; m.position.z += (Math.floor(i / 3) - 0.5) * 0.06;
        });
      }).then(() => toks);
    }
    removeAll(objs){ objs.forEach(o => this.scene.remove(o)); }

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
        default: this.applyAfter(entry); return;
      }
    }
    async playDeploy(e){
      await this.focusZones([e.to], 700, 4.2);
      const at = zoneWorld(e.to), toks = [];
      const mat = new THREE.MeshStandardMaterial({ color: COL[e.faction + 'Hex'], metalness: 0.3, roughness: 0.5 });
      const n = Math.min(6, e.n);
      for(let i = 0; i < n; i++){
        const m = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.05, 0.1, 8), mat); m.castShadow = true;
        m.position.set(at.x + (i % 3 - 1) * 0.08, 2, at.z + 0.12 + Math.floor(i / 3) * 0.08); this.scene.add(m); toks.push(m);
      }
      await this.animate(700, t => toks.forEach((m, i) => {
        const tt = Math.max(0, Math.min(1, t * 1.4 - i * 0.07)); const b = tt < 1 ? 1 - easeOut(tt) : 0;
        m.position.y = 0.05 + b * 2 + (tt > 0.85 ? Math.sin((tt - 0.85) / 0.15 * Math.PI) * 0.04 : 0);
      }));
      this.pulseRing(e.to, COL[e.faction + 'Hex']);
      this.applyAfter(e); this.floatText(e.to, `+${e.n} 💤`, e.faction);
      await this.wait(350);
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
      const w = this.pieces[e.to].wall;
      await this.animate(700, t => { w.children.forEach((s, i) => { const tt = Math.max(0, Math.min(1, t * 1.6 - i * 0.04)); s.position.y = -0.04 + easeOut(tt) * 0.07; }); });
      this.pulseRing(e.to, 0xd8c8a0); this.floatText(e.to, '🧱 Fortified', e.faction);
      await this.wait(500);
    }
    async playBuild(e){
      await this.focusZones([e.to], 700, 3.6);
      this.applyAfter(e);
      const obj = e.kind === 'stronghold' ? (this.pieces[e.to].hold || this.pieces[e.to].tower) : this.pieces[e.to].tent;
      await this.animate(800, t => { obj.scale.set(1, Math.max(0.01, easeOut(t)), 1); });
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
      const toks = await this.marchTokens(this.arcCurve(e.from, e.to, 0.1), e.n, att, 900);
      const A = zoneWorld(e.from), B = zoneWorld(e.to);
      const mid = A.clone().lerp(B, 0.62);
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
        await this.flash(mid, 0xffc070, 1.2);
        this.shake(260, 0.08);
        attLeft -= r.al; defLeft -= r.dl;
        if(r.al) this.floatText(e.from, `-${r.al}`, 'loss');
        if(r.dl) this.floatText(e.to, `-${r.dl}`, 'loss');
        await this.wait(650);
      }
      this.clearDice();
      if(e.rounds.length > 3){
        const rest = e.rounds.slice(3); let al = 0, dl = 0; rest.forEach(r => { al += r.al; dl += r.dl; });
        this.floatText(e.to, `${rest.length} more round${rest.length > 1 ? 's' : ''}: -${al} / -${dl}`, 'sum');
        for(let i = 0; i < Math.min(4, rest.length); i++){ this.flash(mid.clone().add(new THREE.Vector3((Math.random() - 0.5) * 0.4, 0, (Math.random() - 0.5) * 0.3)), 0xff9a50, 0.8); this.shake(160, 0.05); await this.wait(220); }
      }
      this.removeAll(toks);
      arrow.remove();
      if(e.captured){
        this.applyAfter(e);
        this.pulseRing(e.to, COL[att + 'Hex']); this.flash(B, att === 'horde' ? 0xff5030 : 0x60a0ff, 2.2);
        const fl = this.pieces[e.to].flagModel || this.pieces[e.to].flag;
        await this.animate(600, t => { fl.scale.set(1, Math.max(0.05, 1 - Math.sin(t * Math.PI) * 0.95), 1); });
        this.floatText(e.to, '⚑ Captured!', att);
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
      let drag = null; const pts = new Map();
      el.addEventListener('contextmenu', e => e.preventDefault());
      el.addEventListener('pointerdown', e => {
        el.setPointerCapture(e.pointerId); pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
        drag = { x: e.clientX, y: e.clientY, moved: 0, btn: e.button, pinch: pts.size === 2 ? this.pinchDist(pts) : 0 };
      });
      el.addEventListener('pointermove', e => {
        if(!drag){
          const k = this.pickZone(e.clientX, e.clientY);
          el.style.cursor = k ? 'pointer' : 'grab';
          if(this.opts.onHover) this.opts.onHover(k, e);
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
          if(this.doorModel && this.toggleDoor){
            const r = this.renderer.domElement.getBoundingClientRect();
            this.mouse.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
            this.raycaster.setFromCamera(this.mouse, this.camera);
            if(this.raycaster.intersectObject(this.doorModel, true).length){ this.toggleDoor(); pts.clear(); drag = null; return; }
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
      this.renderer.setSize(w, h); this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    }

    // ----- frame -----
    tick(){
      const now = performance.now();
      const dt = Math.min(0.1, (now - (this._last || now)) / 1000); this._last = now;
      (this.mixers || []).forEach(m => m.update(dt));
      if(this.water){ this.water.offset.x = now / 90000; this.water.offset.y = Math.sin(now / 7000) * 0.03; }
      this.anims = this.anims.filter(a => {
        const t = Math.min(1, (now - a.t0) / a.ms); a.fn(t);
        if(t >= 1){ a.res(); return false; } return true;
      });
      this.applyCamera();
      // flags wave, rings breathe
      KEYS.forEach(k => {
        const p = this.pieces[k], pos = p.flagGeo.attributes.position, b = p.base;
        for(let i = 0; i < pos.count; i++){ const x = b[i * 3] + 0.1; pos.array[i * 3 + 2] = Math.sin(now / 260 + x * 30 + p.seed) * 0.018 * x * 8; }
        pos.needsUpdate = true;
        const isSel = this.selected === k, isTgt = (this.highlights || []).includes(k);
        p.ring.material.opacity = isSel ? 0.85 : isTgt ? 0.45 + 0.35 * Math.sin(now / 220) : 0;
        p.ring.material.color.setHex(isSel ? 0xffd36a : 0xff7050);
      });
      this.flames.forEach(f => {
        const k = 0.8 + 0.12 * Math.sin(now / 90 + f.seed) + 0.08 * Math.sin(now / 37 + f.seed * 3);
        f.l.intensity = f.base * k; f.f.scale.y = (f.s === 1 ? 0.4 : 2.2) * (0.9 + 0.15 * k);
      });
      this.dust.rotation.y = now / 60000;
      (this.ships || []).forEach(s => { s.rotation.z = Math.sin(now / 1400 + s.userData.bob) * 0.04; s.rotation.x = Math.sin(now / 1900 + s.userData.bob) * 0.03; });
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
        v.copy(p.grp.position); v.y = 0.5; v.project(this.camera);
        p.lab.style.transform = `translate(-50%,-100%) translate(${(v.x + 1) / 2 * w}px,${(1 - v.y) / 2 * h}px)`;
        p.lab.style.opacity = v.z < 1 ? '' : '0';
        const close = this.cam.dist < 13;
        p.lab.style.fontSize = (close ? Math.max(10, Math.min(15, 120 / this.cam.dist)) : 9) + 'px';
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
