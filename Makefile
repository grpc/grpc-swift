all:
	swift build
	cp .build/debug/protoc-gen-swift .
	cp .build/debug/protoc-gen-swiftgrpc .

plugin:
	swift build --product protoc-gen-swift -c release -Xswiftc -static-stdlib
	swift build --product protoc-gen-swiftgrpc -c release -Xswiftc -static-stdlib
	cp .build/release/protoc-gen-swift .
	cp .build/release/protoc-gen-swiftgrpc .

project:
	swift package $(CFLAGS) generate-xcodeproj --output SwiftGRPC.xcodeproj
	@-ruby fix-project-settings.rb SwiftGRPC.xcodeproj || echo "Consider running 'sudo gem install xcodeproj' to automatically set correct indentation settings for the generated project."

test: all
	swift test

test-plugin:
	swift build --product protoc-gen-swiftgrpc
	protoc Sources/Examples/EchoNIO/echo.proto --proto_path=Sources/Examples/EchoNIO --plugin=.build/debug/protoc-gen-swift --plugin=.build/debug/protoc-gen-swiftgrpc --swiftgrpc_out=/tmp --swiftgrpc_opt=NIO=true
	diff -u /tmp/echo.grpc.swift Sources/Examples/EchoNIO/Generated/echo.grpc.swift

test-generate-linuxmain:
ifeq ($(UNAME_S), Darwin)
	swift test --generate-linuxmain
	@git diff --exit-code */LinuxMain.swift */XCTestManifests.swift > /dev/null || { echo "Generated tests are out-of-date; run 'swift test --generate-linuxmain' to update them!"; exit 1; }
else
	echo "test-generate-linuxmain is only available on Darwin"
endif

clean:
	-rm -rf Packages
	-rm -rf .build build
	-rm -rf SwiftGRPC.xcodeproj
	-rm -rf Package.pins Package.resolved
	-rm -rf protoc-gen-swift protoc-gen-swiftgrpc
	-cd Examples/Google/Datastore && make clean
	-cd Examples/Google/NaturalLanguage && make clean
	-cd Examples/Google/Spanner && make clean
