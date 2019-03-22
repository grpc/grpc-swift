UNAME_S = $(shell uname -s)

ifeq ($(UNAME_S),Linux)
else
  CFLAGS = -Xcc -ISources/BoringSSL/include -Xlinker -lz
endif

all:
	swift build $(CFLAGS)
	cp .build/debug/protoc-gen-swift .
	cp .build/debug/protoc-gen-swiftgrpc .

plugin:
	swift build $(CFLAGS) --product protoc-gen-swift -c release -Xswiftc -static-stdlib
	swift build $(CFLAGS) --product protoc-gen-swiftgrpc -c release -Xswiftc -static-stdlib
	cp .build/release/protoc-gen-swift .
	cp .build/release/protoc-gen-swiftgrpc .

project:
	swift package $(CFLAGS) generate-xcodeproj --output SwiftGRPC.xcodeproj
	@-ruby fix-project-settings.rb SwiftGRPC.xcodeproj || echo "Consider running 'sudo gem install xcodeproj' to automatically set correct indentation settings for the generated project."

project-carthage:
	swift package generate-xcodeproj --output SwiftGRPC-Carthage.xcodeproj
	@sed -i '' -e "s|$(PWD)|..|g" SwiftGRPC-Carthage.xcodeproj/project.pbxproj
	@sed -i '' -e "s|$(PWD)|../../..|g" SwiftGRPC-Carthage.xcodeproj/GeneratedModuleMap/BoringSSL/module.modulemap
	@ruby fix-project-settings.rb SwiftGRPC-Carthage.xcodeproj || echo "xcodeproj ('sudo gem install xcodeproj') is required in order to generate the Carthage-compatible project!"
	@ruby patch-carthage-project.rb SwiftGRPC-Carthage.xcodeproj || echo "xcodeproj ('sudo gem install xcodeproj') is required in order to generate the Carthage-compatible project!"

test: all
	swift test $(CFLAGS)

test-echo: all
	cp .build/debug/Echo .
	./Echo serve & /bin/echo $$! > echo.pid
	./Echo get | tee test.out
	./Echo expand | tee -a test.out
	./Echo collect | tee -a test.out
	./Echo update | tee -a test.out
	kill -9 `cat echo.pid`
	diff -u test.out Sources/Examples/Echo/test.gold

test-echo-nio: all
	cp .build/debug/EchoNIO .
	cp .build/debug/Echo .
	./EchoNIO serve & /bin/echo $$! > echo.pid
	./Echo get | tee test.out
	./Echo expand | tee -a test.out
	./Echo collect | tee -a test.out
	./Echo update | tee -a test.out
	kill -9 `cat echo.pid`
	diff -u test.out Sources/Examples/Echo/test.gold

test-plugin:
	swift build $(CFLAGS) --product protoc-gen-swiftgrpc
	protoc Sources/Examples/Echo/echo.proto --proto_path=Sources/Examples/Echo --plugin=.build/debug/protoc-gen-swift --plugin=.build/debug/protoc-gen-swiftgrpc --swiftgrpc_out=/tmp --swiftgrpc_opt=TestStubs=true
	diff -u /tmp/echo.grpc.swift Sources/Examples/Echo/Generated/echo.grpc.swift

test-plugin-nio:
	swift build $(CFLAGS) --product protoc-gen-swiftgrpc
	protoc Sources/Examples/Echo/echo.proto --proto_path=Sources/Examples/Echo --plugin=.build/debug/protoc-gen-swift --plugin=.build/debug/protoc-gen-swiftgrpc --swiftgrpc_out=/tmp --swiftgrpc_opt=NIO=true
	diff -u /tmp/echo.grpc.swift Sources/Examples/EchoNIO/Generated/echo.grpc.swift

xcodebuild: project
		xcodebuild -project SwiftGRPC.xcodeproj -configuration "Debug" -parallelizeTargets -target SwiftGRPC -target Echo -target Simple -target protoc-gen-swiftgrpc build

build-carthage:
	carthage build -project SwiftGRPC-Carthage.xcodeproj --no-skip-current

build-carthage-debug:
	carthage build -project SwiftGRPC-Carthage.xcodeproj --no-skip-current --configuration Debug --platform iOS, macOS

clean:
	-rm -rf Packages
	-rm -rf .build build
	-rm -rf SwiftGRPC.xcodeproj
	-rm -rf Package.pins Package.resolved
	-rm -rf protoc-gen-swift protoc-gen-swiftgrpc
	-cd Examples/Google/Datastore && make clean
	-cd Examples/Google/NaturalLanguage && make clean
	-cd Examples/Google/Spanner && make clean
