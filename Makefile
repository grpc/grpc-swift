UNAME_S = $(shell uname -s)

ifeq ($(UNAME_S),Linux)
else
  CFLAGS = -Xcc -ISources/BoringSSL/include -Xlinker -lz
endif

all:
	swift build $(CFLAGS)
	cp .build/debug/protoc-gen-swift .
	cp .build/debug/protoc-gen-swiftgrpc .
	
project:
	swift package $(CFLAGS) generate-xcodeproj
	@-ruby fix-project-settings.rb || echo "Consider running 'sudo gem install xcodeproj' to automatically set correct indentation settings for the generated project."

test:	all
	swift test $(CFLAGS)

test-echo:	all
	cp .build/debug/Echo .
	./Echo serve & /bin/echo $$! > echo.pid
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

xcodebuild: project
		xcodebuild -configuration "Debug" -parallelizeTargets -target SwiftGRPC -target Echo -target Simple -target protoc-gen-swiftgrpc build

clean:
	-rm -rf Packages
	-rm -rf .build build
	-rm -rf SwiftGRPC.xcodeproj
	-rm -rf Package.pins Package.resolved
	-rm -rf protoc-gen-swift protoc-gen-swiftgrpc
	-cd Examples/Echo/PackageManager && make clean
	-cd Examples/Simple/PackageManager && make clean
