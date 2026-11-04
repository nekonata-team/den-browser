# Install dependencies for the web project.
[working-directory: "web"]
install:
    vp install --frozen-lockfile

# Start the web development server.
[working-directory: "web"]
dev:
    vp run dev

# Build the web static site.
[working-directory: "web"]
build: install
    vp run build

# Preview the built web static site locally.
[working-directory: "web"]
preview: build
    vp run preview
