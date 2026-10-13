/* Guild War board: the war room, the table, the generated zone map, the pieces on it, the camera and the
   battle animations. Everything is drawn in code for now (placeholder art until the real assets land).
   Map space (2000 x 1200, y down) -> table space: X = x/200 - 5, Z = y/200 - 3, table top at y = 0. */
(function(){
  const MW = WAR_MAP_SIZE.w, MH = WAR_MAP_SIZE.h;
  const RW = 1000, RH = 600;                       // ownership raster (half the map resolution)
  const KEYS = Object.keys(WAR_LAYOUT);
  const COL = {
    horde: [178, 34, 28], alliance: [36, 84, 190], neutral: [120, 110, 92],
    hordeHex: 0xb3221c, allianceHex: 0x2454be, neutralHex: 0x8a7f6a
  };
  const toWorld = (x, y) => new THREE.Vector3(x / 200 - 5, 0, y / 200 - 3);
  const zoneWorld = k => toWorld(WAR_LAYOUT[k].x, WAR_LAYOUT[k].y);
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const ease = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  const easeOut = t => 1 - Math.pow(1 - t, 3);

  // ---------- the map raster: which zone owns each pixel ----------
  function noise(x, y){
    return Math.sin(x * 0.021 + Math.sin(y * 0.013) * 2) * 0.5 + Math.sin(y * 0.027 + x * 0.008) * 0.35 + Math.sin((x + y) * 0.06) * 0.15;
  }
  function buildRaster(){
    const idx = new Int8Array(RW * RH).fill(-1);
    const pts = KEYS.map(k => WAR_LAYOUT[k]);
    for(let py = 0; py < RH; py++){
      for(let px = 0; px < RW; px++){
        const x = px * 2, y = py * 2;
        let best = -1, bd = 1e9;
        for(let i = 0; i < pts.length; i++){
          const p = pts[i], dx = x - p.x, dy = y - p.y;
          const d = Math.sqrt(dx * dx + dy * dy) / p.r;
          if(d < bd){ bd = d; best = i; }
        }
        if(bd < 1.32 + noise(x, y) * 0.16) idx[py * RW + px] = best;
      }
    }
    return idx;
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
      this.raster = buildRaster();
      this.zoneIdx = {}; KEYS.forEach((k, i) => { this.zoneIdx[k] = i; });
      this.centers = KEYS.map(k => WAR_LAYOUT[k]);
      this.renderer = new THREE.WebGLRenderer({ antialias: true });
      this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
      this.renderer.shadowMap.enabled = true; this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
      this.renderer.outputEncoding = THREE.sRGBEncoding;
      container.appendChild(this.renderer.domElement);
      this.overlay = document.createElement('div'); this.overlay.className = 'wb-overlay'; container.appendChild(this.overlay);
      this.scene = new THREE.Scene(); this.scene.background = new THREE.Color(0x0b0806); this.scene.fog = new THREE.Fog(0x0b0806, 16, 34);
      this.camera = new THREE.PerspectiveCamera(42, 1, 0.05, 80);
      this.cam = { target: new THREE.Vector3(0, 0, 0.2), dist: 10.5, polar: 0.62, az: 0 }; this.shakeOff = new THREE.Vector3();
      this.glow = glowTex();
      this.buildRoom(); this.loadTable(); this.loadStrongholds(); this.buildMap(); this.buildDice();
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
        horde:    { url: 'models/war/horde-stronghold.gltf',    drop: /interior|foyer/i, size: 0.5, rotY: Math.PI },
        alliance: { url: 'models/war/alliance-stronghold.gltf', drop: /cellar|war_room|armordealer|weapondealer|generalarea/i, size: 0.5, rotY: -Math.PI / 2 }
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
            if(mat.map){ mat.map.anisotropy = 4; mat.alphaTest = 0.5; mat.transparent = false; }
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

    // ----- the map on the table -----
    buildMap(){
      const c = document.createElement('canvas'); c.width = 2048; c.height = 1229;
      this.mapCanvas = c; this.mapCtx = c.getContext('2d');
      this.rasterCanvas = document.createElement('canvas'); this.rasterCanvas.width = RW; this.rasterCanvas.height = RH;
      // parchment grain, made once
      this.grain = canvasTex(512, 512, (g, w, h) => {
        const im = g.createImageData(w, h);
        for(let i = 0; i < w * h; i++){ const v = 200 + Math.random() * 55; im.data[i * 4] = v; im.data[i * 4 + 1] = v; im.data[i * 4 + 2] = v; im.data[i * 4 + 3] = 255; }
        g.putImageData(im, 0, 0);
      }).image;
      // resource icons (the site's 2D icons; ore is drawn until it has one)
      const R2 = 'https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/';
      this.resIcons = {};
      Object.entries({ food: 'FoodIcon.png', wood: 'WoodIcon.png', crystal: 'CrystalIcon2.png' }).forEach(([r, f]) => {
        const im = new Image(); im.crossOrigin = 'anonymous';
        im.onload = () => { this.resIcons[r] = im; this.drawMap(); };
        im.src = R2 + f;
      });
      this.resIcons.ore = canvasTex(96, 96, (g) => {
        g.fillStyle = '#5c5a58'; g.beginPath(); g.moveTo(14, 70); g.lineTo(26, 30); g.lineTo(52, 16); g.lineTo(80, 34); g.lineTo(86, 70); g.lineTo(56, 84); g.closePath(); g.fill();
        g.fillStyle = '#7d7b78'; g.beginPath(); g.moveTo(26, 30); g.lineTo(52, 16); g.lineTo(58, 44); g.lineTo(32, 52); g.closePath(); g.fill();
        g.fillStyle = '#c9a24a'; [[40, 60, 7], [64, 52, 6], [58, 70, 5], [30, 44, 4]].forEach(([x, y, r]) => { g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill(); });
        g.strokeStyle = '#2a241e'; g.lineWidth = 3; g.beginPath(); g.moveTo(14, 70); g.lineTo(26, 30); g.lineTo(52, 16); g.lineTo(80, 34); g.lineTo(86, 70); g.lineTo(56, 84); g.closePath(); g.stroke();
      }).image;
      this.mapTex = new THREE.CanvasTexture(c); this.mapTex.anisotropy = 8; this.mapTex.encoding = THREE.sRGBEncoding;
      const m = new THREE.Mesh(new THREE.PlaneGeometry(10, 6), new THREE.MeshStandardMaterial({ map: this.mapTex, roughness: 0.92 }));
      m.rotation.x = -Math.PI / 2; m.position.y = 0.0; m.receiveShadow = true;
      this.scene.add(m); this.mapMesh = m;
      this.drawMap();
    }
    ownerOf(k){ return this.state && this.state.zones[k] ? this.state.zones[k].owner : 'neutral'; }
    drawMap(){
      const g = this.mapCtx, W = 2048, H = 1229, sx = W / MW, sy = H / MH;
      const rc = this.rasterCanvas.getContext('2d'), im = rc.createImageData(RW, RH), d = im.data, R = this.raster;
      const owners = KEYS.map(k => this.ownerOf(k));
      const sel = this.selected != null ? this.zoneIdx[this.selected] : -1;
      const hl = new Set((this.highlights || []).map(k => this.zoneIdx[k]));
      for(let y = 0; y < RH; y++){
        for(let x = 0; x < RW; x++){
          const i = y * RW + x, z = R[i], o = i * 4;
          if(z < 0){
            // sea: darker teal parchment, shallows near the coast
            let near = false;
            for(let dy = -3; dy <= 3 && !near; dy += 3) for(let dx = -3; dx <= 3; dx += 3){ const xx = x + dx, yy = y + dy; if(xx >= 0 && yy >= 0 && xx < RW && yy < RH && R[yy * RW + xx] >= 0){ near = true; break; } }
            d[o] = near ? 120 : 82; d[o + 1] = near ? 132 : 98; d[o + 2] = near ? 118 : 96; d[o + 3] = 255;
            continue;
          }
          // border: a neighbour belongs to another zone
          const r = x + 1 < RW ? R[i + 1] : z, b = y + 1 < RH ? R[i + RW] : z, l = x > 0 ? R[i - 1] : z, t = y > 0 ? R[i - RW] : z;
          const coast = r < 0 || b < 0 || l < 0 || t < 0;
          const border = !coast && (r !== z || b !== z || l !== z || t !== z);
          let pr = 222, pg = 202, pb = 156;
          const c = COL[owners[z]];
          const a = owners[z] === 'neutral' ? 0.08 : 0.42;
          pr = pr * (1 - a) + c[0] * a; pg = pg * (1 - a) + c[1] * a; pb = pb * (1 - a) + c[2] * a;
          if(z === sel){ pr = Math.min(255, pr * 1.18 + 20); pg = Math.min(255, pg * 1.18 + 18); pb = Math.min(255, pb * 1.1 + 6); }
          else if(hl.has(z)){ pr = Math.min(255, pr + 26); pg = Math.min(255, pg + 22); pb = pb + 4; }
          if(border){ pr = 70; pg = 48; pb = 28; }
          if(coast){ pr = 52; pg = 38; pb = 24; }
          d[o] = pr; d[o + 1] = pg; d[o + 2] = pb; d[o + 3] = 255;
        }
      }
      rc.putImageData(im, 0, 0);
      g.imageSmoothingEnabled = true;
      g.drawImage(this.rasterCanvas, 0, 0, W, H);
      g.globalCompositeOperation = 'multiply'; g.globalAlpha = 0.5; g.drawImage(this.grain, 0, 0, W, H); g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
      // routes
      WAR_ROUTES.forEach(rt => {
        const a = WAR_LAYOUT[rt.a], b = WAR_LAYOUT[rt.b];
        const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy);
        const bend = rt.kind === 'zeppelin' ? -0.18 : 0.14;
        const cx = mx - dy / L * L * bend, cy = my + dx / L * L * bend;
        g.setLineDash(rt.kind === 'zeppelin' ? [6, 14] : [18, 12]); g.lineWidth = rt.kind === 'zeppelin' ? 3 : 4;
        g.strokeStyle = rt.kind === 'zeppelin' ? 'rgba(92,52,20,0.8)' : 'rgba(30,58,80,0.75)';
        g.beginPath(); g.moveTo(a.x * sx, a.y * sy); g.quadraticCurveTo(cx * sx, cy * sy, b.x * sx, b.y * sy); g.stroke();
        g.setLineDash([]);
        g.font = '22px serif'; g.fillStyle = '#2d1e10'; g.textAlign = 'center';
        g.fillText(rt.kind === 'zeppelin' ? '🎈' : '⛵', (0.25 * a.x + 0.5 * cx + 0.25 * b.x) * sx, (0.25 * a.y + 0.5 * cy + 0.25 * b.y) * sy);
      });
      // compass rose + continent names + zone names
      g.save(); g.translate(1010, 1080); g.strokeStyle = '#3a2a18'; g.fillStyle = '#3a2a18'; g.lineWidth = 2;
      g.beginPath(); g.arc(0, 0, 60, 0, Math.PI * 2); g.stroke();
      for(let i = 0; i < 4; i++){ g.rotate(Math.PI / 2); g.beginPath(); g.moveTo(0, -80); g.lineTo(12, 0); g.lineTo(-12, 0); g.fill(); }
      g.restore();
      g.textAlign = 'center'; g.fillStyle = 'rgba(40,26,12,0.55)'; g.font = 'italic 700 58px Cinzel, serif';
      g.fillText('K A L I M D O R', 430 * sx, 1180 * sy); g.fillText('EASTERN KINGDOMS', 1490 * sx, 55 * sy);
      // resource icons: every zone shows its type faintly; this game's rich deposits are bold with a gold ring
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], r = WAR_ZONES[k].resource, im = this.resIcons && this.resIcons[r];
        const rich = this.state && this.state.rich ? !!this.state.rich[k] : false;
        const cx = (p.x + 44) * sx, cy = (p.y - 6) * sy, size = rich ? 50 : 38;
        g.save();
        if(rich){
          g.globalAlpha = 0.9; g.strokeStyle = '#d6a940'; g.lineWidth = 4; g.fillStyle = 'rgba(255,236,170,0.35)';
          g.beginPath(); g.arc(cx, cy, size * 0.62, 0, Math.PI * 2); g.fill(); g.stroke();
        }
        g.globalAlpha = rich ? 0.95 : 0.36;
        if(im) g.drawImage(im, cx - size / 2, cy - size / 2, size, size);
        else { g.font = `${size * 0.7}px serif`; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText({ food: '🍖', wood: '🪵', crystal: '💎', ore: '⛏' }[r], cx, cy); }
        g.restore();
      });
      g.textBaseline = 'alphabetic';
      KEYS.forEach(k => {
        const p = WAR_LAYOUT[k], z = WAR_ZONES[k];
        g.font = `600 ${p.r > 90 ? 22 : 19}px Cinzel, serif`;
        g.lineWidth = 5; g.strokeStyle = 'rgba(240,226,190,0.85)'; g.fillStyle = '#2a1a0c';
        const yy = p.y * sy + 52;
        g.strokeText(z.name, p.x * sx, yy); g.fillText(z.name, p.x * sx, yy);
        if(z.capital){ g.font = 'italic 15px serif'; g.strokeText(z.capital, p.x * sx, yy + 18); g.fillText(z.capital, p.x * sx, yy + 18); }
      });
      // a burnt vignette round the edge of the parchment
      const vg = g.createRadialGradient(W / 2, H / 2, H * 0.45, W / 2, H / 2, W * 0.62);
      vg.addColorStop(0, 'rgba(60,30,10,0)'); vg.addColorStop(1, 'rgba(40,20,6,0.65)');
      g.fillStyle = vg; g.fillRect(0, 0, W, H);
      this.mapTex.needsUpdate = true;
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
      const p = { k, grp, flag, flagMat, roof, tower, tent, wall, ring, lab, flagGeo, base: flagGeo.attributes.position.array.slice(), seed: Math.random() * 10 };
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
      await this.tweenCam({ target: new THREE.Vector3(0, 0, 0.2), dist: 10.5, polar: 0.62, az: 0 }, 3200);
    }
    focusZones(keys, ms, dist){
      const v = new THREE.Vector3(); keys.forEach(k => v.add(zoneWorld(k))); v.multiplyScalar(1 / keys.length);
      let spread = 0; keys.forEach(k => { spread = Math.max(spread, zoneWorld(k).distanceTo(v)); });
      return this.tweenCam({ target: v, dist: dist || Math.max(3.2, spread * 2.6 + 2.6), polar: 0.78 }, ms || 900);
    }
    overview(ms){ return this.tweenCam({ target: new THREE.Vector3(0, 0, 0.2), dist: 10.5, polar: 0.62, az: 0 }, ms || 900); }
    continent(which){
      return this.tweenCam({ target: which === 'kalimdor' ? new THREE.Vector3(-2.6, 0, 0.1) : new THREE.Vector3(2.5, 0, 0.1), dist: 6.6, polar: 0.66, az: 0 }, 1000);
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
        const fl = this.pieces[e.to].flag;
        await this.animate(600, t => { fl.scale.set(1, Math.max(0.05, Math.abs(Math.cos(t * Math.PI))), 1); });
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
      const px = Math.floor(hit.uv.x * RW), py = Math.floor((1 - hit.uv.y) * RH);
      const z = this.raster[Math.max(0, Math.min(RH - 1, py)) * RW + Math.max(0, Math.min(RW - 1, px))];
      return z >= 0 ? KEYS[z] : null;
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
          this.cam.target.x = Math.max(-6, Math.min(6, this.cam.target.x)); this.cam.target.z = Math.max(-4, Math.min(4, this.cam.target.z));
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
