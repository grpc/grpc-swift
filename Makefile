
CFLAGS = -Xcc -ISources/BoringSSL/include

LDFLAGS = -Xlinker -lz 

all:
	swift package generate-xcodeproj
	swift build -v $(CFLAGS) $(LDFLAGS)
	

test:
	swift build -v $(CFLAGS) $(LDFLAGS)
	swift test -v $(CFLAGS) $(LDFLAGS) 

clean:
	rm -rf Packages
	rm -rf .build
	rm -rf SwiftGRPC.xcodeproj
	rm -rf Package.pins
