import type { SoftwareApplication, WithContext } from "schema-dts";
import screen from "@/assets/screens/01-postaja.webp";
import { LATEST_RELEASE_URL, SITE_DESCRIPTION, SITE_NAME } from "./site";

/** SoftwareApplication JSON-LD for the homepage: free Android app, Slovenian. */
export function appSchema(site: URL | undefined): WithContext<SoftwareApplication> {
	const url = site?.href ?? "/";
	return {
		"@context": "https://schema.org",
		"@type": "SoftwareApplication",
		"@id": `${url}#app`,
		name: SITE_NAME,
		description: SITE_DESCRIPTION,
		url,
		applicationCategory: "TravelApplication",
		operatingSystem: "Android",
		inLanguage: "sl",
		isAccessibleForFree: true,
		downloadUrl: LATEST_RELEASE_URL,
		installUrl: LATEST_RELEASE_URL,
		screenshot: new URL(screen.src, site ?? "https://prometnik.dz0ny.dev").href,
		offers: { "@type": "Offer", price: "0", priceCurrency: "EUR" },
		publisher: { "@id": `${url}#organization` },
		countriesSupported: "SI",
	};
}
