/* When the active pet throws something across the screen (pets/FLOW.md §8).
   At most once per quarter of the clock hour, so at most 4 an hour. Each quarter's plan is
   worked out from the quarter's number, so reloading the page can't re-roll it.
   Loaded as a classic script (window.ThrowSchedule) or with require() in tests. */
(function (root) {
  const Pets = root.Pets || (typeof require !== 'undefined' ? require('./generate-pet.js') : null);
  const QUARTER_MS = 15 * 60 * 1000;
  const CHANCE = 0.5;

  // Quarters count from the Unix epoch. Every time zone is offset by a multiple of 15 minutes,
  // so these line up with :00, :15, :30 and :45 on the member's clock.
  const quarterOf = ms => Math.floor(ms / QUARTER_MS);

  // The planned throw time in a quarter, or null if that quarter has none. salt varies it per member.
  function planQuarter(quarter, salt = 0) {
    const rand = Pets.mulberry32((quarter ^ salt) >>> 0);
    if (rand() >= CHANCE) return null;
    return quarter * QUARTER_MS + Math.floor(rand() * QUARTER_MS);
  }

  // The next throw at or after now, skipping the quarter that already had one (lastQuarter).
  function nextThrow(now, { lastQuarter = null, salt = 0, lookahead = 16 } = {}) {
    for (let q = quarterOf(now); q < quarterOf(now) + lookahead; q++) {
      if (q === lastQuarter) continue;
      const at = planQuarter(q, salt);
      if (at !== null && at >= now) return { quarter: q, at };
    }
    return null;
  }

  const api = { QUARTER_MS, CHANCE, quarterOf, planQuarter, nextThrow };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ThrowSchedule = api;
})(typeof window !== 'undefined' ? window : globalThis);
