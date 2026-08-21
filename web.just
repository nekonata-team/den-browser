# Install dependencies for the web project.
[working-directory: "web"]
install:
    pnpm install --frozen-lockfile

# Start the web development server.
[working-directory: "web"]
dev:
    pnpm dev

# Build the web static site.
[working-directory: "web"]
build: install
    pnpm build

# Preview the built web static site locally.
[working-directory: "web"]
preview: build
    pnpm preview
