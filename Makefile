
CFLAGS = -Xcc -ISources/BoringSSL/include

all:
	swift package generate-xcodeproj
	swift build -v $(CFLAGS)
	
test:
	swift build -v $(CFLAGS)
	swift test -v $(CFLAGS)

clean:
	rm -rf Packages
	rm -rf .build
	rm -rf SwiftGRPC.xcodeproj
	rm -rf Package.pins Package.resolved
