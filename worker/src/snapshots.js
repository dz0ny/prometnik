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
const CONCURRENCY = 4;
const RUN_BUDGET_MS = 40000;
// The camera hosts are slow and stall in bursts; the cron can afford to wait
// much longer than a viewer's request.
const CRON_FETCH_TIMEOUT_MS = 25000;
const CAMERAS_KEY = 'meta/station-cameras.json';

// Hourly history only for weather-station cameras: they sit on the roads
// people check for conditions. The ~550 DARS traffic cameras are left out.
const CAMERA_FEEDS = ['https://www.ceste.si/Vremenske/Vreme/KamereInVreme'];

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

// ── Weather history ──────────────────────────────────────────────────────
// Once an hour the weather-station feed's readings are appended to one
// rolling R2 object, so the app can chart the last 24 hours per station.

const WEATHER_FEED = 'https://www.ceste.si/Vremenske/Vreme/KamereInVreme';
const WEATHER_KEY = 'w/last24.json';
const WEATHER_HOURS = 25;

/** Compact readings per station: id → [tempC, humidity%, windKmh, gustKmh, rainMm]. */
export function weatherPoints(feed) {
  const out = {};
  if (!Array.isArray(feed)) return out;
  for (const s of feed) {
    const w = s?.weather;
    if (!w || s.stationId == null) continue;
    out[s.stationId] = [
      w.outdoorTemperatureC ?? null,
      w.humidityPercentage ?? null,
      w.windSpeedKmh ?? null,
      w.windGustKmh ?? null,
      w.dailyRainMm ?? null,
    ];
  }
  return out;
}

/** Adds [stamp]'s readings to the rolling document, keeping the newest hours. */
export function mergeWeatherHour(doc, stamp, stations) {
  const hours = (doc?.hours ?? []).filter((h) => h.stamp !== stamp);
  hours.push({ stamp, stations });
  hours.sort((a, b) => a.stamp.localeCompare(b.stamp));
  return { hours: hours.slice(-WEATHER_HOURS) };
}

/** One station's series from the rolling document, oldest first. */
export function stationSeries(doc, id) {
  const out = [];
  for (const h of doc?.hours ?? []) {
    const p = h.stations?.[id];
    const at = stampToDate(h.stamp);
    if (!p || !at) continue;
    out.push({
      at: at.toISOString().replace('.000Z', 'Z'),
      t: p[0],
      h: p[1],
      w: p[2],
      g: p[3],
      r: p[4],
    });
  }
  return out;
}

async function readWeatherDoc(env) {
  const obj = await env.SNAPS.get(WEATHER_KEY);
  if (!obj) return { hours: [] };
  try {
    return await obj.json();
  } catch {
    return { hours: [] };
  }
}

/** Stores this hour's weather readings once. Returns true when it wrote. */
export async function captureWeather(env, now) {
  const stamp = hourStamp(now);
  const doc = await readWeatherDoc(env);
  if (doc.hours.some((h) => h.stamp === stamp)) return false;
  const res = await fetch(WEATHER_FEED, {
    headers: { 'User-Agent': 'prometnik-cams/1.0' },
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(`weather feed answered ${res.status}`);
  const stations = weatherPoints(await res.json());
  if (Object.keys(stations).length === 0) return false;
  await env.SNAPS.put(
    WEATHER_KEY,
    JSON.stringify(mergeWeatherHour(doc, stamp, stations)),
    { httpMetadata: { contentType: 'application/json' } },
  );
  return true;
}

/** GET /weather?id=<stationId> → {"station", "points": [{at,t,h,w,g,r}]} */
export async function handleWeather(url, env) {
  const id = url.searchParams.get('id') || '';
  if (!/^\d{1,9}$/.test(id)) return json({ error: 'Bad station id' }, 400);
  const doc = await readWeatherDoc(env);
  return json({ station: Number(id), points: stationSeries(doc, id) }, 200, 600);
}

/** GET /status — whether the camera feeds are reachable from the worker. */
export async function handleStatus(env) {
  const feeds = await Promise.all(
    CAMERA_FEEDS.map(async (feed) => {
      try {
        const res = await fetch(feed, {
          headers: { 'User-Agent': 'prometnik-cams/1.0' },
          signal: AbortSignal.timeout(15000),
        });
        const body = await res.text();
        return { feed, status: res.status, cameras: camerasFromFeeds([body]).length };
      } catch (err) {
        return { feed, error: err.message };
      }
    }),
  );
  let lastRun = null;
  try {
    const obj = await env.SNAPS.get('meta/last-run.json');
    if (obj) lastRun = await obj.json();
  } catch {
    // no run recorded yet
  }
  return json({ lastRun, feeds }, 200);
}

/**
 * The camera list for a cron run. A feed that times out would shrink the
 * list for that run, so the largest recent list is kept in R2 and used
 * whenever the live one comes back smaller.
 */
async function knownCameras(env) {
  const live = await listCameras();
  let saved = [];
  try {
    const obj = await env.SNAPS.get(CAMERAS_KEY);
    if (obj) saved = (await obj.json()).cameras ?? [];
  } catch {
    // no saved list yet
  }
  if (live.length >= saved.length * 0.9) {
    if (live.length !== saved.length) {
      await env.SNAPS.put(CAMERAS_KEY, JSON.stringify({ cameras: live }));
    }
    return live;
  }
  return saved;
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
  try {
    const result = await captureSliceInner(env, now, fetchFrame);
    await recordRun(env, { at: now.toISOString(), ok: true, ...result });
  } catch (err) {
    await recordRun(env, { at: now.toISOString(), ok: false, error: String(err) });
    throw err;
  }
}

/** Last cron outcome, shown by /status. */
async function recordRun(env, run) {
  try {
    await env.SNAPS.put('meta/last-run.json', JSON.stringify(run));
  } catch (err) {
    console.warn(`recordRun: ${err.message}`);
  }
}

async function captureSliceInner(env, now, fetchFrame) {
  // Hourly weather readings ride along; a failure here must not stop the
  // camera snapshots.
  let weather = false;
  try {
    weather = await captureWeather(env, now);
  } catch (err) {
    console.warn(`weather history: ${err.message}`);
  }

  const slice = now.getUTCMinutes() % SLICES;
  const stamp = hourStamp(now);
  const cameras = await knownCameras(env);

  // A run either reaches the camera host or it doesn't (it depends on where
  // Cloudflare runs the cron). So every run takes all cameras whose minute
  // has come and that have no frame for this hour yet: a run that can reach
  // the host catches up on what the unlucky ones before it missed.
  const doneKey = `meta/done-${stamp}.json`;
  let done = new Set();
  try {
    const obj = await env.SNAPS.get(doneKey);
    if (obj) done = new Set(await obj.json());
  } catch {
    // first run of the hour
  }
  const mine = [];
  for (const cam of cameras) {
    const id = await cameraId(cam);
    if (sliceOf(id) <= slice && !done.has(id)) {
      mine.push({ cam, id, key: `h/${id}/${stamp}.jpg`, own: sliceOf(id) === slice });
    }
  }
  mine.sort((a, b) => Number(b.own) - Number(a.own));

  let stored = 0;
  let failed = 0;
  let skipped = 0;
  const errors = [];
  const started = Date.now();
  const fetchOne = async (job) => {
    try {
      if (!(await env.SNAPS.head(job.key))) {
        const res = await fetchFrame(new URL(job.cam), CRON_FETCH_TIMEOUT_MS);
        const wrote = await storeHourly(
          env,
          job.cam,
          await res.arrayBuffer(),
          res.headers.get('Content-Type'),
          now,
        );
        if (wrote) stored++;
      }
      done.add(job.id);
      return true;
    } catch (err) {
      failed++;
      if (errors.length < 3) errors.push(`${job.cam.split('/').pop()}: ${err.message}`);
      return false;
    }
  };

  // Probe with up to three cameras; if none answers, this run can't reach
  // the host and stops without hammering it.
  const queue = [...mine];
  let reachable = false;
  for (let i = 0; i < 3 && queue.length > 0 && !reachable; i++) {
    reachable = await fetchOne(queue.shift());
  }
  if (reachable) {
    const worker = async () => {
      for (let job = queue.shift(); job; job = queue.shift()) {
        if (Date.now() - started > RUN_BUDGET_MS) {
          queue.unshift(job);
          return;
        }
        await fetchOne(job);
      }
    };
    await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  }
  skipped = queue.length;
  if (stored > 0 || done.size > 0) {
    await env.SNAPS.put(doneKey, JSON.stringify([...done]));
  }
  console.log(
    `slice ${slice} @${stamp}: ${mine.length} cameras, ${stored} stored, ${failed} failed (of ${cameras.length} total)`,
  );
  return { slice, stamp, cameras: mine.length, stored, failed, total: cameras.length, weather, skipped, errors };
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
