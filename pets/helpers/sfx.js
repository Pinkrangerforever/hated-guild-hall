/* Companion sounds (pets/FLOW.md §7). Every pet sound goes through here, so the member's
   Pet sounds setting silences all of them.

     Sfx.enabled = prefs.sounds;     // the Pet sounds setting
     Sfx.play('chime');              // site-standard sounds, generated in code: tick, crack, fanfare, chime, whoosh
     Sfx.call(monster, base);        // the monster's own call from monster.json sounds.call, if it has one

   Browsers block sound until the member has clicked something on the page; until then, play() does nothing. */
(function (root) {
  let ctx;
  const audio = () => (ctx = ctx || new (root.AudioContext || root.webkitAudioContext)());

  function tone(freq, ms, { type = 'sine', gain = 0.08, slideTo, delay = 0 } = {}) {
    const a = audio(), t = a.currentTime + delay, dur = ms / 1000;
    const osc = a.createOscillator(), amp = a.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, t + dur);
    amp.gain.setValueAtTime(gain * Sfx.volume, t);
    amp.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    osc.connect(amp).connect(a.destination);
    osc.start(t);
    osc.stop(t + dur);
  }

  // A filtered noise burst that sweeps down: the sound of something flying past.
  function whoosh() {
    const a = audio(), dur = 0.6, t = a.currentTime;
    const buffer = a.createBuffer(1, Math.floor(a.sampleRate * dur), a.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    const src = a.createBufferSource(), filter = a.createBiquadFilter(), amp = a.createGain();
    src.buffer = buffer;
    filter.type = 'bandpass';
    filter.Q.value = 1.2;
    filter.frequency.setValueAtTime(2400, t);
    filter.frequency.exponentialRampToValueAtTime(500, t + dur);
    amp.gain.setValueAtTime(0.0001, t);
    amp.gain.exponentialRampToValueAtTime(0.12 * Sfx.volume, t + 0.15);
    amp.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(filter).connect(amp).connect(a.destination);
    src.start(t);
  }

  const SOUNDS = {
    tick: () => tone(1760, 70, { gain: 0.05 }),
    crack: () => tone(900, 120, { type: 'triangle', gain: 0.05, slideTo: 300 }),
    fanfare: () => [523, 784, 1047].forEach((f, i) => tone(f, 160 + i * 50, { gain: 0.06, delay: i * 0.11 })),
    chime: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 350, { gain: 0.06, delay: i * 0.09 })),
    wobble: () => tone(260, 60, { type: 'square', gain: 0.025 }),
    whoosh,
  };

  function canPlay() {
    if (!Sfx.enabled) return false;
    // navigator.userActivation says whether the member has interacted with the page yet.
    const ua = root.navigator && root.navigator.userActivation;
    return !ua || ua.hasBeenActive;
  }

  function play(name) {
    if (!canPlay() || !SOUNDS[name]) return;
    try { SOUNDS[name](); } catch (e) { /* sound is optional */ }
  }

  // monster: monster.json; base: its folder URL, such as 'monsters/baby/'.
  function call(monster, base) {
    const c = monster && monster.sounds && monster.sounds.call;
    if (!c || !canPlay()) return;
    try {
      const el = new Audio(base.replace(/\/?$/, '/') + c.src);
      el.volume = Math.min(1, (c.volume ?? 0.6) * Sfx.volume);
      el.play().catch(() => {});
    } catch (e) { /* sound is optional */ }
  }

  const Sfx = { play, call, enabled: true, volume: 0.7 };
  root.Sfx = Sfx;
})(window);
