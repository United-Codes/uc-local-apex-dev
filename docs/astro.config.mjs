// @ts-check
import { unified } from "@astrojs/markdown-remark";
import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightImageZoom from "starlight-image-zoom";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
	site: "https://united-codes.com/products/uc-local-apex-dev/docs",
	base: "/products/uc-local-apex-dev/docs",
	// starlight-image-zoom does not yet support Astro 7's default "Sätteri"
	// Markdown processor, so opt back into the unified() processor.
	// See https://github.com/HiDeoo/starlight-image-zoom/issues/63
	markdown: {
		processor: unified(),
	},
	integrations: [
		starlight({
			title: "uc-local-apex-dev",
			logo: {
				src: "./src/assets/logo/logo-horizontal-primary-dark.svg",
			},
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/United-Codes/uc-local-apex-dev",
				},
				{
					icon: "linkedin",
					label: "LinkedIn",
					href: "https://www.linkedin.com/company/united-codes/",
				},
				{
					icon: "x.com",
					label: "X/Twitter",
					href: "https://x.com/united_codes",
				},
				{
					icon: "blueSky",
					label: "Bluesky",
					href: "https://bsky.app/profile/united-codes.com",
				},
				{
					icon: "youtube",
					label: "YouTube",
					href: "https://www.youtube.com/@united-codes",
				},
			],
			sidebar: [
				{
					label: "uc-local-apex-dev",
					items: ["index"],
				},
				{
					label: "Getting Started",
					items: ["getting-started", "other/podman-on-mac"],
				},
				{
					label: "Guides",
					items: [
						"getting-started/creating-users",
						"getting-started/backups",
						"getting-started/plsql-debugging",
						"getting-started/install-apps-scripts",
						"getting-started/common-tasks",
					],
				},
				{
					label: "Reference",
					items: ["reference/commands"],
				},
				{
					label: "Migrations",
					items: [{ autogenerate: { directory: "migrations" } }],
				},
				{
					label: "Other",
					items: ["other/faq"],
				},
			],
			customCss: ["./src/styles/uc.css"],
			components: {
				Footer: "./src/components/Footer.astro",
				Head: "./src/components/Head.astro",
			},
			plugins: [
				starlightLinksValidator({ errorOnLocalLinks: false }),
				starlightImageZoom(),
			],
		}),
	],
});
