.PHONY: run release app icon test clean

run:
	swift run

# With only the Command Line Tools installed, swift-testing needs its framework
# pointed at explicitly and its Foundation cross-import overlay disabled — that
# overlay ships without a module and fails to resolve.
test:
	@set -eu; \
	fw=/Library/Developer/CommandLineTools/Library/Developer/Frameworks; \
	if [ "$$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] && [ -d "$$fw/Testing.framework" ]; then \
		swift test -Xswiftc -F -Xswiftc "$$fw" -Xlinker -F -Xlinker "$$fw" \
			-Xlinker -rpath -Xlinker "$$fw" \
			-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays; \
	else \
		swift test; \
	fi

release:
	swift build -c release

app:
	./scripts/make-app.sh

icon:
	@set -eu; \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	swift scripts/render-icon.swift "$$tmp/owl-1024.png"; \
	mkdir "$$tmp/AppIcon.iconset"; \
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s "$$tmp/owl-1024.png" --out "$$tmp/AppIcon.iconset/icon_$${s}x$${s}.png" >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d "$$tmp/owl-1024.png" --out "$$tmp/AppIcon.iconset/icon_$${s}x$${s}@2x.png" >/dev/null; \
	done; \
	iconutil -c icns "$$tmp/AppIcon.iconset" -o assets/AppIcon.icns

clean:
	swift package clean
	rm -rf build
