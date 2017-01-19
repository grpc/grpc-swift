
CFLAGS = \
-Xcc -DOPENSSL_NO_ASM \
-Xcc -ISources/BoringSSL/include \
-Xcc -ISources/CgRPC 

LDFLAGS = -Xlinker -lz 

test:
	swift build $(CFLAGS) $(LDFLAGS)
	swift test $(CFLAGS) $(LDFLAGS) 

clean :
	rm -rf Packages
	rm -rf .build
