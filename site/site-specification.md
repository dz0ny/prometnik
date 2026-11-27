# Site Specification

## Configuration
- **Site Type**: General (single product landing page + legal/support pages for Google Play)
- **Target Audience**: drivers in Slovenia checking roads before a trip (commuters, winter mountain-pass drivers, truck drivers, holiday traffic towards the coast and Karavanke); secondarily Play Store reviewers looking for the privacy/support URLs
- **Primary Goal**: install the app (Android APK now; Google Play and App Store later)
- **Language**: Slovenian only (`lang="sl"`), like Gozdar. English skipped.
- **Production URL**: https://prometnik.dz0ny.dev (to be served by `../worker` (`prometnik-cams`) as Workers Static Assets)
- **Reserved paths**: the worker API owns `/cam`, `/history`, `/snap`, `/status`, `/weather`. No page may start with these.

## Design Read
Reading this as: a product landing page for Slovenian drivers, with a calm, practical, "check before you go" feel, leaning a dark night-road aesthetic that matches the app's navy UI and its icon (navy, white road, sky-blue camera, amber signal).

## Directions considered (decided without an interview — the user was not available)
- **A. "Nočna cesta"** (chosen) — Dark language, cool navy near-black from the icon, sky blue from the app's primary for data, one signal-amber highlight (the icon's signal arcs, app tertiary) for anything you press. Overpass (Highway Gothic heritage, road-sign letterforms) used decisively for both display and body, Overpass Mono only for readings. Asymmetric split hero with two real phone screenshots; thin road-network lines as the only ornament; dashed amber lane marking as a section rule.
- B. "Prometni znak" — Light, road-sign white/yellow with hard black type, brutalist sign panels. Rejected: every screenshot is a dark UI, so on a light page they would look pasted in; yellow-on-white also fails contrast for text.
- C. "Kamera v živo" — Full-bleed webcam media mask with a scrim. Rejected: webcam frames belong to DARS/DRSI/ARSO and the available captures carry pixelated privacy masks; at full bleed that is the first thing anyone would see.

## Design Direction
- **Direction**: "Nočna cesta" — the site looks like the app at night: navy surfaces, sky blue for data, amber for anything you should press, road lines as the map motif.
- **Base Language**: Dark (with a Technology-style mono accent for numbers only)
- **Dials**: VARIANCE 6 · MOTION 5 · DENSITY 4
  - VARIANCE 6: left-aligned 7/5 split hero with an overlapping tilted phone, bento feature grid, one split band, one full-bleed band; no centered hero.
  - MOTION 5: one orchestrated hero entrance + IntersectionObserver scroll reveals (hidden only when JS runs, `.js` class), CTA lift on hover. All behind `prefers-reduced-motion: no-preference`.
  - DENSITY 4: `--spacing-section` 6rem (4rem mobile), 76rem container.
- **Palette** (60/30/10): dominant #08111f (bg) / #0f1b2d (card) · secondary #5da9e9 sky (data, icons) with #1b3a5b sky-deep fills (the travel-times band) · accent #ffb547 signal amber (CTAs, key numbers, lane marks). Navy hue OKLCH h≈258, amber h≈73: ≈ complementary (185°) rather than strict triadic, because both hues are taken from the app icon/UI so site and app match (same reasoning as Gozdar's tan). Neutrals are derived from the navy hue at low chroma (C 0.03–0.05).
- **Fonts**: Overpass 300–900 variable (display + body) / Overpass Mono 400–700 (readings only: `38 min`, `+7 min`, `−2,0 °C`) — Google via Astro Fonts API, subsets `latin` + `latin-ext` (č š ž). One decisive family instead of a weak pair; the mono is an accent, not a second lead.
- **Signature patterns**: Asymmetric Split hero (overlapping tilted phone), Bento (6 cells, "Dogodki na karti" lead cell with road lines), Column list ("In še to"), Split band (camera history, screenshot left), Full-bleed band (travel times on sky-deep), card grid (download), Column list in a card (data sources).
- **Motion recipes**: Orchestrated Entrance, Scroll Reveal, Magnetic CTA (lift only).

### Palette (OKLCH, computed)
```
background        #08111f  oklch(0.177 0.032 259)
card              #0f1b2d  oklch(0.221 0.039 258)
muted             #1a283d  oklch(0.275 0.044 258)
border            #2a3a52  oklch(0.346 0.047 258)
foreground        #eef2f7  oklch(0.960 0.008 254)
muted-foreground  #a9b6c8  oklch(0.772 0.030 257)
faint             #8593a8  oklch(0.659 0.035 258)
sky               #5da9e9  oklch(0.713 0.121 246)
sky-deep          #1b3a5b  oklch(0.342 0.069 252)
primary (amber)   #ffb547  oklch(0.824 0.149 73)
primary-hover     #ffc56e  oklch(0.858 0.124 76)
```

### Contrast (WCAG 2.x, computed with a script, not estimated)
```
on bg #08111f / card #0f1b2d / muted #1a283d
  foreground        #eef2f7   16.8 / 15.4 / 13.2  ✓
  muted-foreground  #a9b6c8    9.2 /  8.4 /  7.2  ✓ body text
  faint             #8593a8    6.1 /  5.5 /  4.8  ✓ meta text (≥ 4.5 everywhere)
  sky               #5da9e9    7.5 /  6.9 /  5.9  ✓ data text, icons
  primary (amber)   #ffb547   10.8 /  9.8 /  8.5  ✓
  sky-deep          #1b3a5b    1.6 /  1.5 /  1.3  ✗ fills only, never text
  border            #2a3a52    1.6 / 1.5         ✗ lines only
primary-foreground #1d1200 on amber #ffb547: 10.5 ✓ (on hover #ffc56e: 11.8 ✓)
foreground #eef2f7 on sky-deep #1b3a5b: 10.4 ✓ (travel-times band H2)
foreground/85 (≈ #ced6e0) on sky-deep: 7.9 ✓ (travel-times band body)
step cards bg/70 on sky-deep (≈ #0e1d31): foreground 15.1 / muted-foreground 8.2 / amber 9.7 ✓
bg #08111f on sky #5da9e9: 7.5 ✓
```
Stock Tailwind gray/slate/sky utilities are not used for text anywhere; every text colour is a token above.
The destructive token #e5484d (4.4:1 on card) is defined for shadcn but not used on any page; treat it as large-text-only.

## Content sources
- Copy anchored on `../README.md`, `lib/screens/intro_wizard_screen.dart`, `lib/screens/about_screen.dart` (data sources), the sheets in `lib/widgets/` (DRSI fields, burja levels, rest-area fields) and the services in `lib/services/` (every host the app calls).
- Facts checked in code: location permission is while-in-use only (no background location in the manifest), nearby events are computed on the device from the Slovenia-wide feed, notifications are local (`flutter_local_notifications`), the GitHub update check runs only in the non-Play Android build (`selfUpdates`), DRSI CVIS is called over plain HTTP, only allow-listed camera hosts go through the worker, the worker keeps hourly frames in R2 for 2 days and has Cloudflare observability (logs) on.
- "Okoli 170 kamer" comes from the brief, not from a live count.
- Screenshots: four iPhone captures supplied by the user, iOS status bar cropped off, resized to 900 px wide WebP in `src/assets/screens/`. The webcam frames contain the app's pixelated privacy masks; that is intentional.
- OG image: `src/assets/og-image.png`, 1200×630, rendered with headless Chrome from the app icon + the hero headline in Overpass (scratch HTML, not part of the build).

## Design Evolution
- **User customizations**: None yet. 2026-11-27 — built from the Gozdar scaffold; blog dropped.
- **Current style**: Navy night-road site, Overpass Black headlines with an amber second clause, real phone screenshots in thick rounded bezels on black, faint sky-blue road lines behind the hero, lead bento cell and travel-times band, a dashed amber lane marking above the camera-history section, one sky-deep full-bleed band for travel times. Long-form pages (`/zasebnost/`, `/podpora/`) use `.prose-cesta` on a 44rem column.
