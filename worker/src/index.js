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

import { captureSlice, handleHistory, handleSnap } from './snapshots.js';

export const ALLOWED_HOSTS = new Set([
  'kamere.dars.si',
  'www.drsc.si',
  'drsc.si',
  'meteo.arso.gov.si',
]);

const FRESH_SECONDS = 60;
const STALE_SECONDS = 3600;
const ORIGIN_TIMEOUT_MS = 8000;

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
  out.headers.delete('Set-Cookie');
  return out;
}

export async function fetchFrame(cam) {
  const res = await fetch(cam.toString(), {
    headers: { 'User-Agent': 'prometnik-cams/1.0 (+https://github.com/dz0ny/prometnik)' },
    signal: AbortSignal.timeout(ORIGIN_TIMEOUT_MS),
  });
  const type = res.headers.get('Content-Type') || '';
  if (!res.ok || !type.startsWith('image/')) {
    throw new Error(`camera answered ${res.status} ${type}`);
  }
  return res;
}

export default {
  // Hourly history: every 5 minutes snapshot one slice of the cameras.
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
    if (url.pathname !== '/cam') {
      return new Response('Not found', { status: 404 });
    }
    const cam = cameraUrl(url.searchParams.get('u'));
    if (!cam) return new Response('Unknown camera', { status: 400 });

    const cache = caches.default;
    const keys = cacheKeys(cam);

    const fresh = await cache.match(keys.fresh);
    if (fresh) return withHeaders(fresh, FRESH_SECONDS, 'HIT');

    try {
      const origin = await fetchFrame(cam);
      const body = await origin.arrayBuffer();
      const type = origin.headers.get('Content-Type');
      const store = (maxAge) =>
        new Response(body, {
          headers: {
            'Content-Type': type,
            'Cache-Control': `public, max-age=${maxAge}`,
          },
        });
      ctx.waitUntil(
        Promise.all([
          cache.put(keys.fresh, store(FRESH_SECONDS)),
          cache.put(keys.stale, store(STALE_SECONDS)),
        ]),
      );
      return withHeaders(store(FRESH_SECONDS), FRESH_SECONDS, 'MISS');
    } catch (err) {
      const stale = await cache.match(keys.stale);
      if (stale) return withHeaders(stale, 15, 'STALE');
      return new Response(`Camera unavailable: ${err.message}`, {
        status: 502,
        headers: { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' },
      });
    }
  },
};
