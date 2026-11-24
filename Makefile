VERSION ?= 0.1.0
GLYPH   ?= ⇢
APP     := build/LinkRoute.app
DEST    ?= $(HOME)/Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all app test install uninstall clean unsign-identity

all: app

test:
	swift run -c release linkroute-tests

app:
	swift build -c release --product LinkRoute
	rm -rf $(APP) build/AppIcon.iconset
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/LinkRoute" $(APP)/Contents/MacOS/LinkRoute
	sed 's/__VERSION__/$(VERSION)/g' scripts/Info.plist > $(APP)/Contents/Info.plist
	$(APP)/Contents/MacOS/LinkRoute --export-iconset build/AppIcon.iconset "$(GLYPH)"
	iconutil -c icns build/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns
	scripts/sign.sh $(APP)
	@echo "built $(APP)"

install: app
	mkdir -p "$(DEST)"
	-osascript -e 'tell application id "com.ephrin.linkroute" to quit' 2>/dev/null
	rm -rf "$(DEST)/LinkRoute.app"
	cp -R $(APP) "$(DEST)/LinkRoute.app"
	$(LSREGISTER) -f "$(DEST)/LinkRoute.app"
	open "$(DEST)/LinkRoute.app"
	@echo "installed $(DEST)/LinkRoute.app"

uninstall:
	-osascript -e 'tell application id "com.ephrin.linkroute" to quit' 2>/dev/null
	$(LSREGISTER) -u "$(DEST)/LinkRoute.app" || true
	rm -rf "$(DEST)/LinkRoute.app"

clean:
	rm -rf build .build

# Delete the local signing identity (scripts/sign.sh makes a new one on the next build;
# macOS will then ask for the privacy grant once more).
unsign-identity:
	security delete-keychain "$(HOME)/Library/Keychains/linkroute-signing.keychain-db" || true
	rm -f "$(HOME)/.config/linkroute/signing/keychain-password"
