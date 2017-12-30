
all:
	swift build -c release
	cp .build/release/Spanner .

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Spanner Sources/*.pb.swift Sources/*.grpc.swift google.json
	rm -rf Package.resolved
