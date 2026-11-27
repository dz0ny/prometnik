// @ts-check

import cloudflare from "@astrojs/cloudflare";
import react from "@astrojs/react";
import sitemap from "@astrojs/sitemap";
import { agentsSummary } from "@nuasite/agent-summary";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig, fontProviders } from "astro/config";
import astroAgentAnnotate from "astro-agent-annotate";
import favicons from "astro-favicons";
import { defineConfig as viteConfig } from "vite";

const isDevelopment = process.env.NODE_ENV === "development";
const devToolbar = { enabled: isDevelopment };

// https://astro.build/config
export default defineConfig({
	site: "https://prometnik.dz0ny.dev",
	output: "static",
	trailingSlash: "always",
	// No `image.service` key on purpose: Astro's schema default is already
	// `astro/assets/services/sharp`, which is what we want. Setting it explicitly
	// buys nothing — and see the adapter note below before changing `imageService`.
	integrations: [
		react(),
		sitemap({ filter: (page) => !page.includes("/branding/") }),
		agentsSummary(),
		...(devToolbar.enabled ? [astroAgentAnnotate()] : []),
		favicons({
			input: "./src/assets/icon.png",
			name: "Prometnik",
			short_name: "Prometnik",
		}),
	],

	vite: viteConfig({
		cacheDir: ".astro/vite",
		plugins: [tailwindcss()],
		resolve: {
			alias: {
				"@": "/src",
			},
		},
	}),

	build: {
		concurrency: 4,
		// Keep this at "auto" (Astro's default: inline only stylesheets under ~4 kB).
		// Forcing "always" puts the whole compiled Tailwind bundle in a <style> block
		// in every document — byte-identical CSS re-transferred on every navigation.
		inlineStylesheets: "auto",
	},

	server: { port: 4321, host: "0.0.0.0", allowedHosts: true },
	devToolbar,
	// `imageService: "custom"` is load-bearing — do NOT "fix" it to "compile".
	// "custom" is the only branch of the adapter's `setImageConfig()` that leaves
	// Astro's sharp service in place. `prerenderEnvironment: "node"` pairs with it
	// so sharp runs in plain Node during the build, not workerd.
	adapter: isDevelopment
		? undefined
		: cloudflare({ imageService: "custom", prerenderEnvironment: "node" }),

	// Overpass descends from Highway Gothic, the US road-sign face — the site
	// reads like signage. Slovenian needs latin-ext (č, š, ž); without it those
	// glyphs fall back to a system font mid-word.
	fonts: [
		{
			provider: fontProviders.google(),
			name: "Overpass",
			cssVariable: "--font-overpass",
			weights: ["300 900"],
			styles: ["normal"],
			subsets: ["latin", "latin-ext"],
			fallbacks: ["ui-sans-serif", "system-ui", "sans-serif"],
		},
		{
			provider: fontProviders.google(),
			name: "Overpass Mono",
			cssVariable: "--font-overpass-mono",
			weights: ["400 700"],
			styles: ["normal"],
			subsets: ["latin", "latin-ext"],
			fallbacks: ["ui-monospace", "monospace"],
		},
	],
});
