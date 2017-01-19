
CFLAGS = \
-Xcc -DOPENSSL_NO_ASM \
-Xcc -ISources/BoringSSL/include \
-Xcc -ISources/gRPC_Core \
-Xcc -ISources/gRPC_Core/include

LDFLAGS = -Xlinker -lz 

test:
	swift build $(CFLAGS) $(LDFLAGS)
	swift test $(CFLAGS) $(LDFLAGS) -Xlinker -lgRPC_Core

clean :
	rm -rf Packages
	rm -rf .build
