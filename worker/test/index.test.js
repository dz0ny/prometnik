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
