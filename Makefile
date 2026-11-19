.PHONY: install dev test check app build cert clean

install:
	bun install

dev:
	bun tauri dev

test:
	cd src-tauri && cargo test --lib

check:
	bun run check
	cd src-tauri && cargo check --all-targets

# macOS: signed Nyx.app with the "Nyx Dev" cert, installed to /Applications.
app:
	./scripts/mac-app.sh

build:
	bun tauri build

cert:
	./scripts/make-dev-cert.sh

clean:
	cd src-tauri && cargo clean
	rm -rf build .svelte-kit
