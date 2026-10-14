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
  const anchor = k => { const p = WAR_LAYOUT[k], s = PIECE_SHIFT[k] || [0, 0]; return [p.x + s[0], p.y + s[1]]; };
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
  const LANDMARKS = { burning_steppes: { model: 'volcano', size: 0.3 } };   // Blackrock Mountain
  const TERRAIN_MODELS = {
    mountain: { url: 'models/war/mountain.gltf', tint: 0x8d7a66 },   // its texture is pale stone: warm it so snow caps read
    volcano:  { url: 'models/war/blackrock-mountain.gltf', glow: /lava/i }
  };

  // the map's edges curl up like old parchment
  const CURL_BAND = 0.07, CURL_LIFT = 0.28;
  function curlHeight(u, v){
    const e = (d) => d < CURL_BAND ? Math.pow((CURL_BAND - d) / CURL_BAND, 2) : 0;
    const a = Math.max(e(u), e(1 - u)), c = Math.max(e(v), e(1 - v));
    return (a + c + a * c) * CURL_LIFT;
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
      this.buildRoom(); this.loadTable(); this.loadStrongholds(); this.loadFlags(); this.loadScenery(); this.loadTerrainModels(); this.buildMap(); this.buildDice();
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
      // floor and walls
      const floorTex = woodTex('#3b2717', '20,10,4'); floorTex.wrapS = floorTex.wrapT = THREE.RepeatWrapping; floorTex.repeat.set(6, 6);
      const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.MeshStandardMaterial({ map: floorTex, roughness: 0.9 }));
      floor.rotation.x = -Math.PI / 2; floor.position.y = -3.1; floor.receiveShadow = true; S.add(floor); this.floor = floor;
      const st = stoneTex(); st.wrapS = st.wrapT = THREE.RepeatWrapping; st.repeat.set(5, 2);
      const wallMat = new THREE.MeshStandardMaterial({ map: st, roughness: 1 });
      [[0, -11, 0], [-13, 0, Math.PI / 2], [13, 0, -Math.PI / 2]].forEach(([x, z, r]) => {
        const w = new THREE.Mesh(new THREE.PlaneGeometry(30, 14), wallMat); w.position.set(x, 3.9, z); w.rotation.y = r; w.receiveShadow = true; S.add(w);
      });
      // faction banners on the back wall
      [['horde', -5], ['alliance', 5]].forEach(([f, x]) => {
        const c = f === 'horde' ? '#8e1a14' : '#1d3f93', sym = f === 'horde' ? '#1a1a1a' : '#e8c35a';
        const tex = canvasTex(128, 320, (g, w, h) => {
          g.fillStyle = c; g.beginPath(); g.moveTo(0, 0); g.lineTo(w, 0); g.lineTo(w, h); g.lineTo(w / 2, h - 46); g.lineTo(0, h); g.fill();
          g.fillStyle = '#d6a940'; g.fillRect(0, 0, w, 10);
          g.fillStyle = sym; g.font = 'bold 74px serif'; g.textAlign = 'center';
          g.fillText(f === 'horde' ? '☗' : '✠', w / 2, 150);
        });
        const b = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 5.5), new THREE.MeshStandardMaterial({ map: tex, transparent: true, side: THREE.DoubleSide, roughness: 0.95 }));
        b.position.set(x, 4.2, -10.9); S.add(b);
      });
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
      // candles on the corners, braziers in the room
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
      [[-11, -9], [11, -9]].forEach(([x, z]) => {
        const bowl = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.35, 0.5, 14), new THREE.MeshStandardMaterial({ color: 0x2a2420, metalness: 0.6, roughness: 0.5 }));
        bowl.position.set(x, 0.2, z); S.add(bowl);
        const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.15, 3.3, 8), bowl.material); pole.position.set(x, -1.5, z); S.add(pole);
        const f = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glow, color: 0xff8a2a, blending: THREE.AdditiveBlending, depthWrite: false }));
        f.position.set(x, 0.9, z); f.scale.set(1.6, 2.2, 1); S.add(f);
        const l = new THREE.PointLight(0xff7a2a, 1.4, 16, 2); l.position.set(x, 1.4, z); S.add(l);
        this.flames.push({ f, l, s: 4, seed: Math.random() * 100, base: 1.4 });
      });
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
      const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: this.mapTex, roughness: 0.92 }));
      m.add(new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: 0x8c7650, roughness: 1, side: THREE.BackSide })));   // the parchment's back
      m.rotation.x = -Math.PI / 2; m.receiveShadow = true; m.castShadow = true;
      this.scene.add(m); this.mapMesh = m; this.mapGeo = geo;
      this.drawMap();
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
      // routes
      WAR_ROUTES.forEach(rt => {
        const a = WAR_LAYOUT[rt.a], b = WAR_LAYOUT[rt.b];
        const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, dx = b.x - a.x, dy = b.y - a.y;
        const bend = rt.kind === 'zeppelin' ? -0.18 : 0.14;
        const cx = mx - dy * bend, cy = my + dx * bend;
        g.setLineDash(rt.kind === 'zeppelin' ? [8, 16] : [20, 13]); g.lineWidth = rt.kind === 'zeppelin' ? 4 : 5;
        g.strokeStyle = rt.kind === 'zeppelin' ? 'rgba(92,52,20,0.75)' : 'rgba(24,48,70,0.7)';
        g.beginPath(); g.moveTo(a.x * sx, a.y * sy); g.quadraticCurveTo(cx * sx, cy * sy, b.x * sx, b.y * sy); g.stroke();
        g.setLineDash([]);
        g.font = '28px serif'; g.fillStyle = '#2d1e10'; g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText(rt.kind === 'zeppelin' ? '🎈' : '⛵', (0.25 * a.x + 0.5 * cx + 0.25 * b.x) * sx, (0.25 * a.y + 0.5 * cy + 0.25 * b.y) * sy);
      });
      // resource icons: every zone shows its type faintly; this game's rich deposits are bold with a gold ring
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], r = WAR_ZONES[k].resource, im = this.resIcons && this.resIcons[r];
        const rich = this.state && this.state.rich ? !!this.state.rich[k] : false;
        const off = Math.min(46, p.r * 0.45);
        const cx = (p.x + off) * sx, cy = (p.y - off * 0.2) * sy, size = rich ? 54 : 42;
        g.save();
        if(rich){
          g.globalAlpha = 0.9; g.strokeStyle = '#d6a940'; g.lineWidth = 4; g.fillStyle = 'rgba(255,236,170,0.35)';
          g.beginPath(); g.arc(cx, cy, size * 0.62, 0, Math.PI * 2); g.fill(); g.stroke();
        }
        g.globalAlpha = rich ? 0.95 : 0.4;
        if(im) g.drawImage(im, cx - size / 2, cy - size / 2, size, size);
        g.restore();
      });
      // zone names
      g.textAlign = 'center'; g.textBaseline = 'alphabetic';
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], z = WAR_ZONES[k];
        g.font = `700 ${p.r > 60 ? 25 : 21}px Cinzel, serif`;
        g.lineWidth = 6; g.strokeStyle = 'rgba(245,232,200,0.9)'; g.fillStyle = '#24160a';
        const yy = (p.y + Math.min(40, p.r * 0.42)) * sy + 16;
        g.strokeText(z.name, p.x * sx, yy); g.fillText(z.name, p.x * sx, yy);
        if(z.capital){ g.font = 'italic 600 18px serif'; g.strokeText(z.capital, p.x * sx, yy + 21); g.fillText(z.capital, p.x * sx, yy + 21); }
      });
      // darken toward the edges so the curl reads
      const vg = g.createRadialGradient(W / 2, H / 2, H * 0.42, W / 2, H / 2, W * 0.72);
      vg.addColorStop(0, 'rgba(60,30,10,0)'); vg.addColorStop(1, 'rgba(40,20,6,0.55)');
      g.fillStyle = vg; g.fillRect(0, 0, W, H);
      this.mapTex.needsUpdate = true;
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
        const cfg = MOUNTAINS[k], c = freeSpot(k, 18) || freeSpot(k, 10); if(!c) return;
        const proto = cfg.snow ? P.mountainSnow : P.mountain;
        for(let i = 0; i < cfg.count; i++){
          // the first peak is the tallest; the rest crowd round it, smaller, overlapping
          const h = cfg.size * (i ? 0.5 + rnd() * 0.35 : 1);
          const a = rnd() * Math.PI * 2, d = i ? (0.35 + rnd() * 0.45) * cfg.size / PW * MW * 0.9 : 0;
          place(proto, c[0] + Math.cos(a) * d, c[1] + Math.sin(a) * d * 0.8, h, rnd() * 6.28);
        }
      });
      Object.keys(LANDMARKS).forEach(k => {
        const cfg = LANDMARKS[k], proto = P[cfg.model], c = proto && (freeSpot(k, 14, true) || freeSpot(k, 6, true)); if(!c) return;
        place(proto, c[0], c[1], cfg.size, 0.6);
        // a little ember glow over the crater
        const at = toWorld(c[0], c[1]);
        const light = new THREE.PointLight(0xff5a1a, 0.6, 1.2, 2); light.position.set(at.x, cfg.size * 1.1, at.z); T.add(light);
        this.flames.push({ f: { scale: { y: 0 } }, l: light, s: 1, seed: rnd() * 100, base: 0.6 });
      });
      // water: a second sheet just above the map, showing over lakes (strong) and the sea (faint)
      const mask = document.createElement('canvas'); mask.width = RW; mask.height = RH;
      const mg = mask.getContext('2d'), mi = mg.createImageData(RW, RH);
      for(let i = 0; i < R.length; i++){ const v = R[i] === LAKE ? 200 : R[i] === SEA ? 70 : 0; mi.data[i * 4] = mi.data[i * 4 + 1] = mi.data[i * 4 + 2] = v; mi.data[i * 4 + 3] = 255; }
      mg.putImageData(mi, 0, 0);
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
        if(model){ p.hold = model.clone(); p.hold.position.set(-0.2, 0.002, -0.06); p.grp.add(p.hold); }
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
        if(drag && drag.moved < 6 && pts.size === 0 && this.opts.onClick) this.opts.onClick(this.pickZone(e.clientX, e.clientY), e);
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
