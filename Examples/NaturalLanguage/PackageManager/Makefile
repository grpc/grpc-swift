
all:
	swift build -c release
	cp .build/release/NaturalLanguage .

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins NaturalLanguage Sources/*.pb.swift Sources/swiftgrpc.log google.json
	rm -rf Package.resolved
