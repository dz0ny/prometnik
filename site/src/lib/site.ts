// Site-wide identity. Feeds page titles, the meta description, and the
// Organization / WebSite / SoftwareApplication JSON-LD.
export const SITE_NAME = "Prometnik";
export const SITE_TAGLINE = "promet, kamere in vreme na slovenskih cestah";
export const SITE_DESCRIPTION =
	"Brezplačna aplikacija za slovenske ceste: dogodki na karti, kamere z zgodovino 24 ur, vreme in stanje cestišča, potovalni časi in opozorila. Brez računa.";

// No e-mail on purpose: support runs through GitHub issues.
export const GITHUB_URL = "https://github.com/dz0ny/prometnik";
export const RELEASES_URL = "https://github.com/dz0ny/prometnik/releases";
export const LATEST_RELEASE_URL = "https://github.com/dz0ny/prometnik/releases/latest";
export const ISSUES_URL = "https://github.com/dz0ny/prometnik/issues";
export const NEW_ISSUE_URL = "https://github.com/dz0ny/prometnik/issues/new";

// Contact details for the Organization schema. Left null where unknown —
// the schema omits what isn't set rather than asserting something wrong.
export const SITE_CONTACT: {
	email: string | null;
	telephone: string | null;
	contactType: string;
	address: {
		streetAddress: string;
		addressLocality: string;
		postalCode: string;
		addressCountry: string;
	} | null;
	sameAs: string[];
} = {
	email: null,
	telephone: null,
	contactType: "customer support",
	address: null,
	sameAs: [GITHUB_URL],
};
