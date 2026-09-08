# Version is defined in Resources/Info.plist (CFBundleShortVersionString 2.3.0 / CFBundleVersion 5).
APP     = EFStatus
BUNDLE  = $(APP).app
EXEC    = $(BUNDLE)/Contents/MacOS/$(APP)
SOURCES = $(wildcard Sources/*.swift)
MIN_OS  = 12.0
SWIFTC_FLAGS = -framework Cocoa -framework UserNotifications -framework CryptoKit -framework Network

.PHONY: all clean run

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Resources/Info.plist Resources/AppIcon.icns
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	swiftc $(SOURCES) $(SWIFTC_FLAGS) \
		-target arm64-apple-macosx$(MIN_OS) \
		-o $(EXEC)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --deep --sign - --identifier com.efstatus.app $(BUNDLE)
	@echo "✓ Built $(BUNDLE) (arm64)"

run: all
	open $(BUNDLE)

clean:
	rm -rf $(BUNDLE)
