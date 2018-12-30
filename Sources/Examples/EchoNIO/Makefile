all:
	swift build -c debug --product EchoNIO
	cp .build/debug/EchoNIO .

project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Echo google.json
	rm -rf Package.resolved EchoNIO.xcodeproj EchoNIO
