
all:
	swift build -c release
	cp .build/release/Datastore .

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Datastore Sources/*.pb.swift Sources/*.grpc.swift google.json
	rm -rf Package.resolved
