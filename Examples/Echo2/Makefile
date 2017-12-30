
all:
	swift build -c release
	cp .build/release/Echo .

project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Echo Sources/*.pb.swift Sources/*.grpc.swift google.json
	rm -rf Package.resolved Echo.xcodeproj
