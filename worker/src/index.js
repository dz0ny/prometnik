// Edge cache for Prometnik webcam images.
//
//   GET /cam?u=<encoded camera image URL>[&t=<anything>]
//
// Camera hosts (DARS, DRSI, ARSO) are slow and far from many users. Frames
// change about once a minute, so every Cloudflare location keeps the latest
// frame for FRESH_SECONDS and answers from there; only the first request per
// location per minute goes to the camera. If the camera is slow or down, the
// last good frame (kept for STALE_SECONDS) is served instead of an error.
//
// The client's `t` cache-buster is ignored for the cache key, so all users
// share one cached frame. Only known camera hosts are proxied (no open proxy).
// Plain-http cameras (www.drsc.si) are served over https, and CORS is open so
// the web build can load them too.

import {
  captureSlice,
  handleHistory,
  handleSnap,
  handleStatus,
  handleWeather,
  latestSnapshot,
  storeHourly,
} from './snapshots.js';

export const ALLOWED_HOSTS = new Set([
  'kamere.dars.si',
  'www.drsc.si',
  'drsc.si',
  'meteo.arso.gov.si',
]);

const FRESH_SECONDS = 60;
const STALE_SECONDS = 86400; // any frame from the last day beats a slow camera
const ORIGIN_TIMEOUT_MS = 8000;
// A stale copy older than this loses to a newer hourly snapshot in R2.
const STALE_PREFER_SNAPSHOT_MS = 10 * 60 * 1000;

/** Validates the `u` parameter; returns the camera URL or null. */
export function cameraUrl(raw) {
  if (!raw) return null;
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (!ALLOWED_HOSTS.has(url.hostname)) return null;
  url.searchParams.delete('t'); // app cache-buster, not part of the frame
  url.hash = '';
  // One identity per camera: feeds list the same picture as http and https,
  // and as drsc.si and www.drsc.si. Without this each variant would get its
  // own cache entry and its own hourly history.
  url.protocol = 'https:';
  if (url.hostname === 'drsc.si') url.hostname = 'www.drsc.si';
  return url;
}

/** Synthetic cache keys: one fresh copy and one longer-lived fallback. */
export function cacheKeys(cam) {
  // Separate hostnames: the Cache API ignores URL fragments, so `#fresh` /
  // `#stale` suffixes would collide.
  const path = `${cam.host}${cam.pathname}${cam.search}`;
  return {
    fresh: new Request(`https://fresh.prometnik-cams.cache/${path}`),
    stale: new Request(`https://stale.prometnik-cams.cache/${path}`),
  };
}

function withHeaders(res, maxAge, state) {
  const out = new Response(res.body, res);
  out.headers.set('Cache-Control', `public, max-age=${maxAge}`);
  out.headers.set('Access-Control-Allow-Origin', '*');
  out.headers.set('X-Cam-Cache', state);
  out.headers.set('Access-Control-Expose-Headers', 'X-Cam-At, X-Cam-Cache');
  out.headers.delete('Set-Cookie');
  return out;
}

/**
 * Whether [buf] is a whole image. Camera hosts sometimes serve the JPEG
 * while the camera is still writing it: the file then stops early (no
 * end-of-image marker) and decodes with a grey bottom, or not at all.
 */
export function isCompleteImage(buf, type) {
  const b = new Uint8Array(buf);
  if (b.length < 4) return false;
  if (!/jpe?g/i.test(type)) return true;
  if (b[0] !== 0xff || b[1] !== 0xd8) return false;
  // The EOI marker may be followed by a little padding.
  for (let i = b.length - 2; i >= Math.max(0, b.length - 64); i--) {
    if (b[i] === 0xff && b[i + 1] === 0xd9) return true;
  }
  return false;
}

/**
 * Fetches one whole frame of [cam]: { body, type }. A half-written frame is
 * fetched again (up to [tries] times) after a short pause.
 */
export async function fetchFrame(cam, timeoutMs = ORIGIN_TIMEOUT_MS, tries = 3) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(cam.toString(), {
      headers: { 'User-Agent': 'prometnik-cams/1.0 (+https://github.com/dz0ny/prometnik)' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const type = res.headers.get('Content-Type') || '';
    if (!res.ok || !type.startsWith('image/')) {
      throw new Error(`camera answered ${res.status} ${type}`);
    }
    const body = await res.arrayBuffer();
    if (isCompleteImage(body, type)) return { body, type };
    if (attempt >= tries) throw new Error('camera sent an incomplete image');
    await new Promise((r) => setTimeout(r, 700));
  }
}

export default {
  // Hourly history: every minute snapshot one slice of the cameras.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(captureSlice(env, event.scheduledTime, fetchFrame));
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        },
      });
    }
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method not allowed', { status: 405 });
    }
    if (url.pathname === '/history') return handleHistory(url, env);
    if (url.pathname === '/snap') return handleSnap(url, env);
    if (url.pathname === '/status') return handleStatus(env);
    if (url.pathname === '/weather') return handleWeather(url, env);
    if (url.pathname !== '/cam') {
      // Not an API path and no site file matched: the site's 404 page.
      if (env.ASSETS) return env.ASSETS.fetch(request);
      return new Response('Not found', { status: 404 });
    }
    const cam = cameraUrl(url.searchParams.get('u'));
    if (!cam) return new Response('Unknown camera', { status: 400 });

    return serveCamera(cam, env, ctx);
  },
};

/**
 * Serve a camera frame, cache first:
 *  1. fresh edge copy (< FRESH_SECONDS)       → HIT
 *  2. this/last hour's R2 snapshot, when newer than an edge copy older than
 *     10 minutes (or there is none)          → SNAPSHOT, refresh in background
 *  3. older edge copy (< STALE_SECONDS)       → STALE, refresh in background
 *  4. nothing cached anywhere                 → fetch the camera (MISS)
 * Only case 4 waits on the (slow) camera; a camera that's down keeps serving
 * its last good frame.
 */
async function serveCamera(cam, env, ctx) {
  const cache = caches.default;
  const keys = cacheKeys(cam);

  const fresh = await cache.match(keys.fresh);
  if (fresh) return withHeaders(fresh, FRESH_SECONDS, 'HIT');

  const refresh = () => refreshFrame(cam, env, keys);

  const stale = await cache.match(keys.stale);
  const staleAt = Date.parse(stale?.headers.get('X-Cam-At') ?? '');
  // A stale edge copy can be hours old when this location hasn't been asked
  // for the camera in a while; the cron's hourly snapshot may be newer.
  const snap =
    env.SNAPS &&
    (!stale || !(Date.now() - staleAt < STALE_PREFER_SNAPSHOT_MS))
      ? await latestSnapshot(env, cam.toString())
      : null;
  if (snap && (!stale || !(staleAt >= snap.uploaded.getTime()))) {
    await stale?.body?.cancel();
    ctx.waitUntil(refresh().catch(() => {}));
    return withHeaders(
      new Response(snap.body, {
        headers: {
          'Content-Type': snap.httpMetadata?.contentType || 'image/jpeg',
          'X-Cam-At': snap.uploaded.toISOString(),
        },
      }),
      15,
      'SNAPSHOT',
    );
  }
  await snap?.body?.cancel();
  if (stale) {
    ctx.waitUntil(refresh().catch(() => {}));
    return withHeaders(stale, 15, 'STALE');
  }

  try {
    const { body, type, at } = await refresh();
    return withHeaders(
      new Response(body, { headers: { 'Content-Type': type, 'X-Cam-At': at } }),
      FRESH_SECONDS,
      'MISS',
    );
  } catch (err) {
    return new Response(`Camera unavailable: ${err.message}`, {
      status: 502,
      headers: { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' },
    });
  }
}

/** Fetch the camera, update both edge copies and this hour's R2 snapshot. */
async function refreshFrame(cam, env, keys) {
  const { body, type } = await fetchFrame(cam);
  // When the frame was fetched, so clients can tell a stale copy's real age.
  const at = new Date().toISOString();
  const store = (maxAge) =>
    new Response(body, {
      headers: {
        'Content-Type': type,
        'Cache-Control': `public, max-age=${maxAge}`,
        'X-Cam-At': at,
      },
    });
  const cache = caches.default;
  await Promise.all([
    cache.put(keys.fresh, store(FRESH_SECONDS)),
    cache.put(keys.stale, store(STALE_SECONDS)),
    env.SNAPS ? storeHourly(env, cam.toString(), body, type) : null,
  ]);
  return { body, type, at };
}
