
CFLAGS = -Xcc -ISources/BoringSSL/include

LDFLAGS = -Xlinker -lz 

test:
	swift build -v $(CFLAGS) $(LDFLAGS)
	swift test -v $(CFLAGS) $(LDFLAGS) 

clean :
	rm -rf Packages
	rm -rf .build
