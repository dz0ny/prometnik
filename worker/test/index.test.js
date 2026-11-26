import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cameraUrl, cacheKeys } from '../src/index.js';

test('accepts known camera hosts and drops the app cache-buster', () => {
  const u = cameraUrl('https://kamere.dars.si/kamere/x/Cam_0001.jpg?t=123');
  assert.equal(u.toString(), 'https://kamere.dars.si/kamere/x/Cam_0001.jpg');
  assert.ok(cameraUrl('http://www.drsc.si/kamere/Neblo/Neb1_0001.jpg'));
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
