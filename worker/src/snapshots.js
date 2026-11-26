// Hourly webcam history.
//
// A cron runs every minute and snapshots one sixtieth of all cameras
// (each camera always falls in the same slice), so every camera gets exactly
// one frame per hour. Frames live in R2 under h/<camera id>/<YYYYMMDDHH>.jpg
// (UTC hour); a bucket lifecycle rule deletes them after 2 days.
//
//   GET /history?u=<camera URL>  → {"camera", "frames": [{"at", "url"}]}
//   GET /snap?k=<key>            → the stored JPEG

import { cameraUrl } from './index.js';

// Cron runs every minute; each run handles one of 60 slices (~10 cameras),
// which keeps a run well under the Workers per-invocation subrequest limit.
export const SLICES = 60;
const HISTORY_HOURS = 24;
const CONCURRENCY = 5;

const CAMERA_FEEDS = [
  // DARS traffic cameras (GeoJSON, properties.Image).
  'https://www.promet.si/dc/agg.kamere.v2',
  // Weather-station cameras (JSON with "cameraLink" fields).
  'https://www.ceste.si/Vremenske/Vreme/KamereInVreme',
];

/** Stable short id for a camera URL (hex SHA-256 prefix). */
export async function cameraId(camUrl) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(camUrl),
  );
  return [...new Uint8Array(digest)]
    .slice(0, 12)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** UTC hour stamp YYYYMMDDHH for [date]. */
export function hourStamp(date) {
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${date.getUTCFullYear()}${p(date.getUTCMonth() + 1)}${p(date.getUTCDate())}` +
    p(date.getUTCHours())
  );
}

/** Parses an hour stamp back to the UTC start of that hour. */
export function stampToDate(stamp) {
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})$/.exec(stamp);
  if (!m) return null;
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4]));
}

/** Which of the [SLICES] cron runs in an hour snapshots this camera. */
export function sliceOf(id) {
  return parseInt(id.slice(0, 8), 16) % SLICES;
}

/** Extracts allowed, normalised camera URLs from feed bodies. */
export function camerasFromFeeds(bodies) {
  const urls = new Set();
  for (const body of bodies) {
    // Both feeds are JSON; a regex over the text tolerates shape changes.
    const re = /"(?:Image|cameraLink)"\s*:\s*"(https?:[^"]+)"/g;
    for (const m of body.matchAll(re)) {
      const cam = cameraUrl(m[1].replace(/\\\//g, '/'));
      if (cam) urls.add(cam.toString());
    }
  }
  return [...urls];
}

async function listCameras() {
  const bodies = await Promise.all(
    CAMERA_FEEDS.map(async (feed) => {
      try {
        const res = await fetch(feed, {
          headers: { 'User-Agent': 'prometnik-cams/1.0' },
          signal: AbortSignal.timeout(15000),
        });
        return res.ok ? await res.text() : '';
      } catch (err) {
        console.warn(`feed ${feed}: ${err.message}`);
        return '';
      }
    }),
  );
  return camerasFromFeeds(bodies);
}

/** R2 key of [camUrl]'s snapshot for the UTC hour of [date]. */
export async function snapshotKey(camUrl, date) {
  return `h/${await cameraId(camUrl)}/${hourStamp(date)}.jpg`;
}

/**
 * Store [body] as this hour's snapshot unless the hour already has one —
 * the single write path, so each camera has at most one frame per hour.
 * Returns true when it wrote.
 */
export async function storeHourly(env, camUrl, body, type, now = new Date()) {
  const key = await snapshotKey(camUrl, now);
  if (await env.SNAPS.head(key)) return false;
  await env.SNAPS.put(key, body, {
    httpMetadata: { contentType: type || 'image/jpeg' },
    customMetadata: { camera: camUrl },
  });
  return true;
}

/** The newest snapshot of [camUrl] from this or the previous hour. */
export async function latestSnapshot(env, camUrl, now = new Date()) {
  for (const back of [0, 1]) {
    const key = await snapshotKey(camUrl, new Date(now.getTime() - back * 3600e3));
    const obj = await env.SNAPS.get(key);
    if (obj) return obj;
  }
  return null;
}

/** Cron handler: snapshot this run's slice of cameras into R2. */
export async function captureSlice(env, scheduledTime, fetchFrame) {
  const now = new Date(scheduledTime);
  const slice = now.getUTCMinutes() % SLICES;
  const stamp = hourStamp(now);
  const cameras = await listCameras();

  const mine = [];
  for (const cam of cameras) {
    const id = await cameraId(cam);
    if (sliceOf(id) === slice) mine.push({ cam, key: `h/${id}/${stamp}.jpg` });
  }

  let stored = 0;
  let failed = 0;
  const queue = [...mine];
  const worker = async () => {
    for (let job = queue.shift(); job; job = queue.shift()) {
      try {
        if (await env.SNAPS.head(job.key)) continue; // already have this hour
        const res = await fetchFrame(new URL(job.cam));
        const wrote = await storeHourly(
          env,
          job.cam,
          await res.arrayBuffer(),
          res.headers.get('Content-Type'),
          now,
        );
        if (wrote) stored++;
      } catch {
        failed++;
      }
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  console.log(
    `slice ${slice} @${stamp}: ${mine.length} cameras, ${stored} stored, ${failed} failed (of ${cameras.length} total)`,
  );
}

/** GET /history?u=… */
export async function handleHistory(url, env) {
  const cam = cameraUrl(url.searchParams.get('u'));
  if (!cam) return json({ error: 'Unknown camera' }, 400);
  const id = await cameraId(cam.toString());
  const listed = await env.SNAPS.list({ prefix: `h/${id}/` });
  const cutoff = Date.now() - HISTORY_HOURS * 3600 * 1000;
  const frames = listed.objects
    .map((o) => {
      const at = stampToDate(o.key.slice(o.key.lastIndexOf('/') + 1, -4));
      return at && {
        at: at.toISOString().replace('.000Z', 'Z'),
        url: `${url.origin}/snap?k=${encodeURIComponent(o.key)}`,
        _t: at.getTime(),
      };
    })
    .filter((f) => f && f._t >= cutoff)
    .sort((a, b) => a._t - b._t)
    .map(({ _t, ...f }) => f);
  return json({ camera: cam.toString(), frames }, 200, 300);
}

/** GET /snap?k=… */
export async function handleSnap(url, env) {
  const key = url.searchParams.get('k') || '';
  if (!/^h\/[0-9a-f]{24}\/\d{10}\.jpg$/.test(key)) {
    return new Response('Bad key', { status: 400 });
  }
  const obj = await env.SNAPS.get(key);
  if (!obj) return new Response('Not found', { status: 404 });
  return new Response(obj.body, {
    headers: {
      'Content-Type': obj.httpMetadata?.contentType || 'image/jpeg',
      // A past hour's frame never changes.
      'Cache-Control': 'public, max-age=86400, immutable',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

function json(body, status = 200, maxAge = 0) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': maxAge ? `public, max-age=${maxAge}` : 'no-store',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
