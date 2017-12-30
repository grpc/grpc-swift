
all:
	swift build -c release
	cp .build/release/NaturalLanguage .

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins NaturalLanguage Sources/*.pb.swift Sources/*.rpc.swift google.json
	rm -rf Package.resolved
