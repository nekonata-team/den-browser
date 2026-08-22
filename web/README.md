# Den Browser website

Static Astro site for Den Browser's public website.

## Local development

From the repository root:

```sh
mise install
just web::install
just web::dev
```

The development server runs at `http://localhost:4321`.

Build the site with:

```sh
just web::build
```

The static output is written to `web/dist/`.

## Cloudflare Pages

The site uses Cloudflare Pages Git integration. Configure the project once in
the Cloudflare dashboard:

- connect the GitHub repository;
- set `main` as the production branch;
- set the root directory to `web`;
- use `pnpm build` as the build command and `dist` as the output directory;
- set the build watch path to `web/**`;
- add `den.nekonata.dev` as a custom domain.

The `nekonata.dev` zone is already managed by Cloudflare. Git integration
provides production deployments from `main` and preview deployments for other
branches and pull requests.

The release flow publishes the Sparkle Appcast at `/appcast.xml`. The file is
generated and committed under `public/` before the Cloudflare Pages deploy.

## Project structure

```text
web/
├── public/
├── src/
│   ├── i18n/
│   ├── layouts/
│   ├── pages/
│   └── styles/
└── package.json
```

Astro exposes `.astro` and Markdown files under `src/pages/` as routes. Static
assets belong in `public/`.
