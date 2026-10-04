/* Site-standard companion animations (pets/FLOW.md). Eggs and pets only supply still art.

     const fx = EggFx.create(container, { eggSrc, size: 96 });
     fx.wobble();                    // one wobble (idle, hover, click)
     fx.checkOff(4, 9);              // wobble and float "4 / 9"
     fx.setAlert(true);              // "!" badge: ready to hatch
     const stop = EggFx.every(() => fx.wobble());   // idle: once every 12-20 s, at random
     EggFx.rock(petImg);             // pets: a small tilt clockwise, then counter-clockwise
     const hatch = await EggFx.hatchAtCenter({ fromEl, eggSrc, petSrc });   // ends showing the pet
     hatch.close();                  // after the congratulations popup
     EggFx.throwItem({ fromEl, item: { emoji: '🍌' } });   // easter egg: fly something across the screen
     EggFx.speed = 3;                // slow motion for tuning (1 = normal)
   Sounds go through window.Sfx (helpers/sfx.js), if it's loaded.
*/
(function (root) {
  const STYLE_ID = 'egg-fx-style';
  // Crack line across the egg, in percent of its box.
  const CRACK = [[0, 47], [11, 53], [22, 44], [33, 54], [44, 45], [55, 55], [66, 45], [77, 53], [88, 44], [100, 51]];

  const CSS = `
  .egg-fx{ position:relative; width:var(--size); height:var(--size); display:inline-block; --s:1; }
  .egg-fx > *{ position:absolute; inset:0; }
  .egg-fx img, .egg-hatch img{ width:100%; height:100%; object-fit:contain; display:block; pointer-events:none; user-select:none; }
  .egg-fx-shadow{ inset:auto 18% 2% 18%; height:9%; border-radius:50%; background:rgba(0,0,0,0.45); filter:blur(3px); }
  .egg-fx-egg, .fx-rock-target{ transform-origin:50% 92%; }

  .egg-fx-egg.wobble, .egg-hatch-egg.wobble{ animation:eggFxWobble calc(0.65s * var(--s, 1)) ease-out; }
  @keyframes eggFxWobble{
    0%{ transform:rotate(0); } 18%{ transform:rotate(-11deg); } 38%{ transform:rotate(8deg); }
    58%{ transform:rotate(-5deg); } 78%{ transform:rotate(2deg); } 100%{ transform:rotate(0); }
  }
  .fx-rock{ animation:eggFxRock calc(0.9s * var(--s, 1)) ease-in-out; }
  @keyframes eggFxRock{ 0%,100%{ transform:rotate(0); } 25%{ transform:rotate(6deg); } 70%{ transform:rotate(-5deg); } }

  .egg-fx-float{
    inset:auto; left:50%; top:4%; white-space:nowrap; pointer-events:none; font:800 18px/1 system-ui, sans-serif; color:#f0dfb4;
    text-shadow:0 2px 6px rgba(0,0,0,0.7); transform:translateX(-50%);
    animation:eggFxFloat calc(1.1s * var(--s)) ease-out forwards;
  }
  @keyframes eggFxFloat{ 0%{ transform:translate(-50%,0); opacity:1; } 100%{ transform:translate(-50%,-60px); opacity:0; } }

  .egg-fx-alert{ inset:auto; right:6%; top:2%; width:26%; height:26%; min-width:20px; min-height:20px; border-radius:50%;
    background:#c0392b; color:#fff; border:2px solid #fff3c4; font:900 calc(var(--size) * .17)/1 system-ui, sans-serif;
    display:flex; align-items:center; justify-content:center; box-shadow:0 2px 8px rgba(0,0,0,.6);
    animation:eggFxAlertIn calc(0.45s * var(--s)) cubic-bezier(.3,1.6,.5,1) both, eggFxAlertPulse calc(1.6s * var(--s)) ease-in-out calc(0.5s * var(--s)) infinite; }
  @keyframes eggFxAlertIn{ from{ transform:scale(0); } to{ transform:scale(1); } }
  @keyframes eggFxAlertPulse{ 0%,100%{ transform:scale(1); } 50%{ transform:scale(1.12); } }

  /* the hatch, centered on screen */
  .egg-hatch{ position:fixed; inset:0; z-index:900; background:rgba(10,7,3,.75); animation:eggFxFade calc(0.3s * var(--s)) ease-out both; }
  .egg-hatch.closing{ animation:eggFxFadeOut calc(0.3s * var(--s)) ease-in both; }
  @keyframes eggFxFade{ from{ opacity:0; } to{ opacity:1; } }
  @keyframes eggFxFadeOut{ from{ opacity:1; } to{ opacity:0; } }
  .egg-hatch-stage{ position:fixed; transition:left calc(0.6s * var(--s)) ease-in-out, top calc(0.6s * var(--s)) ease-in-out,
    width calc(0.6s * var(--s)) ease-in-out, height calc(0.6s * var(--s)) ease-in-out; }
  .egg-hatch-egg{ position:absolute; inset:0; transform-origin:50% 92%; }
  .egg-hatch-pet{ position:absolute; inset:0; opacity:0; }
  .egg-hatch-pet.shown{ opacity:1; animation:eggFxSettle calc(0.5s * var(--s)) ease-out; }
  @keyframes eggFxSettle{ from{ transform:scale(.88); } to{ transform:scale(1); } }
  .egg-fx-cracks{ position:absolute; inset:0; -webkit-mask-size:contain; mask-size:contain; -webkit-mask-repeat:no-repeat; mask-repeat:no-repeat; -webkit-mask-position:center; mask-position:center; }
  .egg-fx-cracks svg{ width:100%; height:100%; display:block; overflow:visible; }
  .egg-fx-cracks path{ fill:none; stroke:#2a1a08; stroke-width:2.6; stroke-linejoin:round; stroke-linecap:round;
    stroke-dasharray:1; stroke-dashoffset:1; animation:eggFxDraw calc(0.45s * var(--s)) ease-out forwards; }
  .egg-fx-cracks path.branch{ stroke-width:1.6; animation-delay:calc(0.2s * var(--s)); }
  @keyframes eggFxDraw{ to{ stroke-dashoffset:0; } }
  .egg-hatch-flash{ position:absolute; inset:-60%; border-radius:50%; pointer-events:none; opacity:0;
    background:radial-gradient(circle, #fff 0%, #fff 45%, rgba(255,250,230,.85) 60%, rgba(255,250,230,0) 72%); }
  .egg-hatch-flash.on{ transition:opacity calc(0.25s * var(--s)) ease-in; opacity:1; }
  .egg-hatch-flash.off{ transition:opacity calc(0.7s * var(--s)) ease-out; opacity:0; }

  /* members who ask for less motion get fades instead of movement */
  @media (prefers-reduced-motion: reduce){
    .egg-fx-egg.wobble, .egg-hatch-egg.wobble, .fx-rock{ animation:none; }
    .egg-fx-alert{ animation:none; }
    .egg-hatch-stage{ transition:none; }
  }`;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  const reducedMotion = () => root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms * EggFx.speed));
  const el = (cls, html = '') => { const d = document.createElement('div'); d.className = cls; d.innerHTML = html; return d; };
  const restart = (node, cls) => { node.classList.remove(cls); void node.offsetWidth; node.classList.add(cls); };

  const sound = name => root.Sfx && root.Sfx.play(name);

  // Calls fn once every min-max ms (EggFx.idleRange by default), at random. Returns a stop function.
  function every(fn, [min, max] = EggFx.idleRange) {
    let timer;
    const next = () => { timer = setTimeout(() => { fn(); next(); }, (min + Math.random() * (max - min)) * EggFx.speed); };
    next();
    return () => clearTimeout(timer);
  }

  function rock(node) {
    ensureStyle();
    node.classList.add('fx-rock-target');
    node.style.setProperty('--s', EggFx.speed);
    restart(node, 'fx-rock');
  }

  function create(container, { eggSrc, size = 96 }) {
    ensureStyle();
    const stage = el('egg-fx');
    stage.style.setProperty('--size', size + 'px');
    stage.append(el('egg-fx-shadow'), el('egg-fx-egg', `<img src="${eggSrc}" alt="">`));
    container.replaceChildren(stage);
    const egg = stage.querySelector('.egg-fx-egg');

    function wobble() {
      stage.style.setProperty('--s', EggFx.speed);
      restart(egg, 'wobble');
    }

    function checkOff(done, total) {
      wobble();
      const f = el('egg-fx-float');
      f.textContent = `${done} / ${total}`;
      stage.appendChild(f);
      setTimeout(() => f.remove(), 1200 * EggFx.speed);
      sound('tick');
    }

    function setAlert(on) {
      const badge = stage.querySelector('.egg-fx-alert');
      if (on && !badge) {
        stage.style.setProperty('--s', EggFx.speed);
        const b = el('egg-fx-alert');
        b.textContent = '!';
        stage.appendChild(b);
      } else if (!on && badge) badge.remove();
    }

    return { wobble, checkOff, setAlert, element: stage, egg };
  }

  // Moves the egg from fromEl to the center of the screen, wobbles twice, cracks, and a white flash
  // reveals the pet. Resolves once the pet is showing; call close() on the result to fade it all out.
  async function hatchAtCenter({ fromEl, eggSrc, petSrc, size = 220 }) {
    ensureStyle();
    const layer = el('egg-hatch');
    layer.style.setProperty('--s', EggFx.speed);
    const from = fromEl.getBoundingClientRect();
    const stage = el('egg-hatch-stage', `
      <div class="egg-hatch-egg"><img src="${eggSrc}" alt=""></div>
      <div class="egg-hatch-pet"><img src="${petSrc}" alt=""></div>
      <div class="egg-hatch-flash"></div>`);
    Object.assign(stage.style, { left: from.left + 'px', top: from.top + 'px', width: from.width + 'px', height: from.height + 'px' });
    layer.appendChild(stage);
    document.body.appendChild(layer);
    const egg = stage.querySelector('.egg-hatch-egg');
    const pet = stage.querySelector('.egg-hatch-pet');
    const flash = stage.querySelector('.egg-hatch-flash');
    const reduce = reducedMotion();

    // 1. To the center.
    void stage.offsetWidth;
    Object.assign(stage.style, {
      left: (root.innerWidth - size) / 2 + 'px', top: (root.innerHeight - size) / 2 + 'px', width: size + 'px', height: size + 'px',
    });
    await wait(reduce ? 50 : 750);

    if (!reduce) {
      // 2. Two wobbles, then the crack.
      for (let i = 0; i < 2; i++) {
        restart(egg, 'wobble');
        sound('wobble');
        await wait(800);
      }
      const line = CRACK.map(([x, y], i) => `${i ? 'L' : 'M'}${x} ${y}`).join(' ');
      const cracks = el('egg-fx-cracks', `<svg viewBox="0 0 100 100" preserveAspectRatio="none">
        <path pathLength="1" d="${line}"/>
        <path class="branch" pathLength="1" d="M33 54 L30 63 L34 70"/>
        <path class="branch" pathLength="1" d="M66 45 L69 36 L65 29"/>
        <path class="branch" pathLength="1" d="M88 44 L92 37"/></svg>`);
      cracks.style.webkitMaskImage = cracks.style.maskImage = `url("${eggSrc}")`;
      egg.appendChild(cracks);
      sound('crack');
      await wait(700);
    }

    // 3. White flash; the egg becomes the pet under it.
    flash.classList.add('on');
    sound('fanfare');
    await wait(350);
    egg.remove();
    pet.classList.add('shown');
    flash.classList.remove('on');
    flash.classList.add('off');
    await wait(700);

    return {
      layer,
      async close() {
        layer.classList.add('closing');
        await wait(300);
        layer.remove();
      },
    };
  }

  // Flies an item ({ emoji } or { src }) from fromEl across the screen in a spinning arc, toward the far side.
  function throwItem({ fromEl, item, size = 40 }) {
    const from = fromEl.getBoundingClientRect();
    const x0 = from.left + from.width / 2, y0 = from.top + from.height / 3;
    const goLeft = x0 > root.innerWidth / 2;
    const x1 = goLeft ? -size * 2 : root.innerWidth + size * 2;
    const y1 = root.innerHeight * (0.25 + Math.random() * 0.4);
    const peak = Math.min(y0, y1) - root.innerHeight * (0.15 + Math.random() * 0.15);
    const node = document.createElement('div');
    node.setAttribute('aria-hidden', 'true');
    node.style.cssText = `position:fixed; left:0; top:0; z-index:800; pointer-events:none; width:${size}px; height:${size}px;
      display:flex; align-items:center; justify-content:center; font-size:${size * 0.9}px; line-height:1;`;
    if (item.src) node.innerHTML = `<img src="${item.src}" alt="" style="width:100%; height:100%; object-fit:contain;">`;
    else node.textContent = item.emoji;
    document.body.appendChild(node);
    // Sample the arc (a quadratic curve) so the motion stays smooth in any browser.
    const frames = [];
    for (let i = 0; i <= 12; i++) {
      const t = i / 12, mx = (x0 + x1) / 2;
      const x = (1 - t) * (1 - t) * x0 + 2 * (1 - t) * t * mx + t * t * x1;
      const y = (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * peak + t * t * y1;
      frames.push({ transform: `translate(${x - size / 2}px, ${y - size / 2}px) rotate(${(goLeft ? -1 : 1) * t * 900}deg)` });
    }
    sound('whoosh');
    const reduce = reducedMotion();
    const anim = node.animate(reduce ? [frames[6], frames[6]] : frames, { duration: (reduce ? 800 : 1500) * EggFx.speed, easing: 'linear' });
    if (reduce) node.animate([{ opacity: 0 }, { opacity: 1 }, { opacity: 0 }], { duration: 800 * EggFx.speed });
    return anim.finished.then(() => node.remove(), () => node.remove());
  }

  const EggFx = { create, every, rock, hatchAtCenter, throwItem, speed: 1, idleRange: [12000, 20000] };
  root.EggFx = EggFx;
})(window);
