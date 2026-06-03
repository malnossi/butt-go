# Makefile for Atheer

WORKSPACE_DIR := $(shell pwd)
DEPS_DIST := $(WORKSPACE_DIR)/deps-dist
DEPS_DIST_LINUX := $(WORKSPACE_DIR)/deps-dist-linux
DEPS_DIST_WINDOWS := $(WORKSPACE_DIR)/deps-dist-windows

# Check OS to apply specific CI-like static linking logic
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
	# macOS Static Linking Configuration
	CGO_CFLAGS  ?= -I$(DEPS_DIST)/include -I$(DEPS_DIST)/include/fdk-aac -I$(DEPS_DIST)/include/opus
	CGO_LDFLAGS ?= -L$(DEPS_DIST)/lib -lportaudio -lmp3lame -lfdk-aac -lopus -logg -lvorbis -lvorbisenc -framework CoreAudio -framework AudioToolbox -framework AudioUnit -framework CoreFoundation -Wl,-w
	PKG_CONFIG_PATH ?= $(DEPS_DIST)/lib/pkgconfig
	
	# Set macOS deployment target dynamically to match the local OS version
	MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion | cut -d. -f1-2)
	export MACOSX_DEPLOYMENT_TARGET
else
	# Fallback/Linux/Windows dynamic/static mixing (can be extended)
	CGO_CFLAGS  ?= -I/opt/homebrew/include -I/opt/homebrew/include/fdk-aac -I/opt/homebrew/include/opus
	CGO_LDFLAGS ?= -L/opt/homebrew/lib -lportaudio -lmp3lame -lfdk-aac -lopus -logg -lvorbis -lvorbisenc -Wl,-w
endif

# Export CGO variables to all child processes spawned by make targets
export CGO_CFLAGS
export CGO_LDFLAGS
export PKG_CONFIG_PATH

WAILS_LDFLAGS ?= -ldflags "-compressdwarf=false -s -w -extldflags '-Wl,-w'"

.PHONY: all dev build test clean deps-macos deps-linux build-linux deps-windows build-windows build-app-image

all: build

# Start the Wails hot-reloading desktop development environment
dev: deps-macos
	wails dev $(WAILS_LDFLAGS)

# Build the final self-signed production application bundle
build:
	wails build --clean $(WAILS_LDFLAGS)

# Execute macOS static dependency build
deps-macos:
	@bash scripts/build_deps_macos.sh

# Execute Linux static dependency build
deps-linux:
	@bash scripts/build_deps_linux.sh

# Build the final self-signed production application bundle for Linux
# Build the final self-signed production application bundle for Linux
build-linux: deps-linux
	PKG_CONFIG_PATH="$(DEPS_DIST_LINUX)/lib/pkgconfig:$$PKG_CONFIG_PATH" CGO_CFLAGS="-I$(DEPS_DIST_LINUX)/include" CGO_LDFLAGS="-L$(DEPS_DIST_LINUX)/lib -Wl,-Bstatic -lportaudio -lmp3lame -lfdk-aac -lopus -lopusfile -logg -lvorbis -lvorbisenc -Wl,-Bdynamic -lasound -lm -lpthread -lrt" wails build -tags webkit2_41 --clean -skipbindings -s $(WAILS_LDFLAGS)

# Execute Windows static dependency build
deps-windows:
	@bash scripts/build_deps_windows.sh

# Build the final self-signed production application bundle for Windows
build-windows: deps-windows
	CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
	PKG_CONFIG_PATH="$(DEPS_DIST_WINDOWS)/lib/pkgconfig:$$PKG_CONFIG_PATH" \
	CGO_CFLAGS="-I$(DEPS_DIST_WINDOWS)/include" \
	CGO_LDFLAGS="-L$(DEPS_DIST_WINDOWS)/lib -Wl,-Bstatic -lportaudio -lmp3lame -lfdk-aac -lopus -lopusfile -logg -lvorbis -lvorbisenc -Wl,-Bdynamic -lwinmm -lole32 -luuid -ldsound -lsetupapi -static-libgcc -static-libstdc++" \
	wails build -platform windows/amd64 --clean -skipbindings -s -nsis $(WAILS_LDFLAGS)

# Build the AppImage for Linux
build-app-image: build-linux
	@echo "Building AppImage..."
	rm -rf build/AppDir
	mkdir -p build/AppDir/usr/bin
	mkdir -p build/AppDir/usr/share/applications
	mkdir -p build/AppDir/usr/share/icons/hicolor/256x256/apps
	cp build/bin/Atheer build/AppDir/usr/bin/Atheer
	cp Atheer.png build/AppDir/Atheer.png
	cp Atheer.png build/AppDir/usr/share/icons/hicolor/256x256/apps/Atheer.png
	cp packaging/appimage/Atheer.desktop build/AppDir/Atheer.desktop
	cp packaging/appimage/Atheer.desktop build/AppDir/usr/share/applications/Atheer.desktop
	ln -sf usr/bin/Atheer build/AppDir/AppRun
	@if [ "$$(uname -m)" = "x86_64" ]; then \
		echo "Downloading appimagetool for x86_64"; \
		curl -fsSLk -o build/appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage; \
	elif [ "$$(uname -m)" = "aarch64" ]; then \
		echo "Downloading appimagetool for aarch64"; \
		curl -fsSLk -o build/appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-aarch64.AppImage; \
	else \
		echo "Unsupported architecture for appimagetool: $$(uname -m)"; exit 1; \
	fi
	chmod +x build/appimagetool
	APPIMAGE_EXTRACT_AND_RUN=1 build/appimagetool build/AppDir build/bin/Atheer-$$(uname -m).AppImage
	@echo "AppImage created at build/bin/Atheer-$$(uname -m).AppImage"

# Run unit tests verifying audio encoding and Icecast source streaming mechanics
test:
	go test -v ./internal/...

# Remove compiled builds and clean go build cache
clean:
	rm -rf build/bin/atheer.app
	go clean
