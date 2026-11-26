import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cameraUrl, cacheKeys } from '../src/index.js';

test('accepts known camera hosts and drops the app cache-buster', () => {
  const u = cameraUrl('https://kamere.dars.si/kamere/x/Cam_0001.jpg?t=123');
  assert.equal(u.toString(), 'https://kamere.dars.si/kamere/x/Cam_0001.jpg');
  // http/https and drsc.si/www.drsc.si are the same camera.
  assert.equal(
    cameraUrl('http://drsc.si/kamere/Neblo/Neb1_0001.jpg').toString(),
    cameraUrl('https://www.drsc.si/kamere/Neblo/Neb1_0001.jpg?t=5').toString(),
  );
});

test('rejects other hosts and schemes (no open proxy)', () => {
  assert.equal(cameraUrl('https://example.com/a.jpg'), null);
  assert.equal(cameraUrl('https://kamere.dars.si.evil.com/a.jpg'), null);
  assert.equal(cameraUrl('file:///etc/passwd'), null);
  assert.equal(cameraUrl('not a url'), null);
  assert.equal(cameraUrl(null), null);
});

test('cache key ignores the buster so all clients share a frame', () => {
  const a = cacheKeys(cameraUrl('https://kamere.dars.si/a.jpg?t=1'));
  const b = cacheKeys(cameraUrl('https://kamere.dars.si/a.jpg?t=2'));
  assert.equal(a.fresh.url, b.fresh.url);
  assert.notEqual(a.fresh.url, a.stale.url);
});

import { hourStamp, stampToDate, sliceOf, camerasFromFeeds, SLICES } from '../src/snapshots.js';

test('hour stamps round-trip in UTC', () => {
  const d = new Date(Date.UTC(2026, 10, 26, 21, 37));
  assert.equal(hourStamp(d), '2026112621');
  assert.equal(stampToDate('2026112621').toISOString(), '2026-11-26T21:00:00.000Z');
  assert.equal(stampToDate('nope'), null);
});

test('every camera falls in one stable slice', () => {
  const s = sliceOf('a1b2c3d4e5f6a1b2c3d4e5f6');
  assert.ok(s >= 0 && s < SLICES);
  assert.equal(s, sliceOf('a1b2c3d4e5f6a1b2c3d4e5f6'));
});

test('feeds yield allowed, de-duplicated camera URLs', () => {
  const dars = '{"features":[{"properties":{"Image":"https://kamere.dars.si/a.jpg"}},{"properties":{"Image":"https://kamere.dars.si/a.jpg?t=1"}}]}';
  const ceste = '[{"cameraLink":"https:\\/\\/kamere.dars.si\\/b.jpg"},{"cameraLink":"https://evil.example/x.jpg"}]';
  assert.deepEqual(camerasFromFeeds([dars, ceste]).sort(), [
    'https://kamere.dars.si/a.jpg',
    'https://kamere.dars.si/b.jpg',
  ]);
});

import { storeHourly, latestSnapshot } from '../src/snapshots.js';

function fakeR2() {
  const objects = new Map();
  let puts = 0;
  return {
    objects,
    get puts() { return puts; },
    async head(k) { return objects.has(k) ? { key: k } : null; },
    async get(k) { return objects.get(k) ?? null; },
    async put(k, body, opts) { puts++; objects.set(k, { body, ...opts }); },
  };
}

test('only one snapshot per camera per hour, however often it is offered', async () => {
  const SNAPS = fakeR2();
  const env = { SNAPS };
  const cam = 'https://kamere.dars.si/a.jpg';
  const t = (h, m) => new Date(Date.UTC(2026, 10, 26, h, m));
  assert.equal(await storeHourly(env, cam, 'one', 'image/jpeg', t(21, 1)), true);
  assert.equal(await storeHourly(env, cam, 'two', 'image/jpeg', t(21, 30)), false);
  assert.equal(await storeHourly(env, cam, 'three', 'image/jpeg', t(21, 59)), false);
  assert.equal(await storeHourly(env, cam, 'next', 'image/jpeg', t(22, 0)), true);
  assert.equal(SNAPS.puts, 2);
  assert.equal(SNAPS.objects.size, 2);
  // The 21:00 frame is the first one offered that hour.
  assert.equal((await latestSnapshot(env, cam, t(21, 45))).body, 'one');
  // At 22:10 the newest is 22:00; at 23:30 it falls back to 22:00 too.
  assert.equal((await latestSnapshot(env, cam, t(22, 10))).body, 'next');
  assert.equal((await latestSnapshot(env, cam, t(23, 30))).body, 'next');
  assert.equal(await latestSnapshot(env, cam, new Date(t(23, 30).getTime() + 3600e3)), null);
});
