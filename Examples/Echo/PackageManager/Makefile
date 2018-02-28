
all:
	swift build -c release --product Echo
	cp .build/release/Echo .

project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Echo google.json
	rm -rf Package.resolved Echo.xcodeproj Echo
