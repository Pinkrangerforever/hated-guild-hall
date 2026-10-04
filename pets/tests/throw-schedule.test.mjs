// The thrown-food easter egg must stay rare: at most once per quarter-hour, even across reloads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const S = require('../helpers/throw-schedule.js');
const HOUR = 60 * 60 * 1000;
const start = Date.UTC(2026, 9, 1, 0, 0, 0);

// Follows the schedule the way the sandbox does: throw, remember the quarter, ask for the next.
function simulate(hours, salt = 7) {
  const throws = [];
  let now = start, last = null;
  while (now < start + hours * HOUR) {
    const next = S.nextThrow(now, { lastQuarter: last, salt });
    if (!next) { now += S.QUARTER_MS; continue; }
    throws.push(next.at);
    last = next.quarter;
    now = next.at + 1;
  }
  return throws;
}

test('never more than one throw in a quarter, or 4 in a clock hour', () => {
  const throws = simulate(2000);
  const quarters = throws.map(S.quarterOf);
  assert.equal(new Set(quarters).size, quarters.length);
  const perHour = {};
  for (const t of throws) perHour[Math.floor(t / HOUR)] = (perHour[Math.floor(t / HOUR)] || 0) + 1;
  assert.ok(Math.max(...Object.values(perHour)) <= 4);
});

test('about half the quarters get a throw, about 2 an hour', () => {
  const perHour = simulate(2000).length / 2000;
  assert.ok(perHour > 1.8 && perHour < 2.2, `${perHour.toFixed(2)} an hour`);
});

test('two throws can land close together across a quarter boundary', () => {
  const throws = simulate(2000);
  assert.ok(throws.some((t, i) => i && t - throws[i - 1] < 5 * 60 * 1000), 'expected some pairs under 5 minutes apart');
});

test('a reload gets the same plan, and never a second throw in a quarter that had one', () => {
  const now = start + 3 * 60 * 1000;
  const first = S.nextThrow(now, { salt: 7 });
  assert.deepEqual(S.nextThrow(now, { salt: 7 }), first);
  const afterReload = S.nextThrow(first.at + 1, { lastQuarter: first.quarter, salt: 7 });
  assert.ok(afterReload.quarter > first.quarter);
});

test('different members get different plans', () => {
  const plans = [1, 2, 3, 4, 5].map(salt => S.nextThrow(start, { salt }).at);
  assert.ok(new Set(plans).size > 1);
});

test('quarters line up with :00, :15, :30 and :45', () => {
  assert.equal(S.quarterOf(Date.UTC(2026, 9, 1, 10, 14, 59)), S.quarterOf(Date.UTC(2026, 9, 1, 10, 0, 0)));
  assert.equal(S.quarterOf(Date.UTC(2026, 9, 1, 10, 15, 0)), S.quarterOf(Date.UTC(2026, 9, 1, 10, 0, 0)) + 1);
});
