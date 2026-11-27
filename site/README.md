# Prometnik website

Landing page, privacy policy (`/zasebnost/`) and support page (`/podpora/`) for https://prometnik.dz0ny.dev.
Astro 7 + Tailwind v4, scaffolded with Hakuto (copied from the Gozdar site). Design decisions: `site-specification.md`.

```sh
bun install
bun run dev      # http://localhost:4321
bun run build    # writes dist/client
bun run check
```

## Deploy

There is no separate Worker for the site. The existing `../worker` Worker (`prometnik-cams`) is to serve
`site/dist/client` through Workers Static Assets, and every path without a matching file (`/cam`, `/history`,
`/snap`, `/status`, `/weather`) still goes to the worker code in `worker/src/index.js`. The site builds no path
under those prefixes.

```sh
cd site && bun install && bun run build
cd ../worker && npx wrangler deploy --dry-run   # check
cd ../worker && npx wrangler deploy
```

Local end-to-end check (site + worker on one origin), once `assets` is wired in `../worker/wrangler.jsonc`:
build the site, then `cd ../worker && npx wrangler dev`.
