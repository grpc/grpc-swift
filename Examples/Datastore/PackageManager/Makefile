
LDFLAGS = -Xlinker -lz 

all:
	swift build -v $(LDFLAGS)
	cp .build/debug/Datastore .

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Datastore Sources/*.pb.swift Sources/swiftgrpc.log
