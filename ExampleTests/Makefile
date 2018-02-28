
all:
	swift build -c release

project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins
	rm -rf Package.resolved ExampleTests.xcodeproj ExampleTests
