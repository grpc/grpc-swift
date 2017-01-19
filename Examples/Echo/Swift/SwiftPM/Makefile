
CFLAGS = \
-Xcc -DOPENSSL_NO_ASM \
-Xcc -IPackages/SwiftGRPC-0.1.4/Sources/BoringSSL/include \
-Xcc -IPackages/SwiftGRPC-0.1.4/Sources/CgRPC \
-Xcc -IPackages/SwiftGRPC-0.1.4/Sources/CgRPC/include

LDFLAGS = -Xlinker -lz 

all:
	swift build -v $(CFLAGS) $(LDFLAGS)

clean :
	rm -rf Packages
	rm -rf .build
