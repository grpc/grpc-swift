# Which Swift to use.
SWIFT:=swift
# Where products will be built; this is the SPM default.
SWIFT_BUILD_PATH:=./.build
SWIFT_BUILD_CONFIGURATION:=debug
SWIFT_FLAGS:=--build-path=${SWIFT_BUILD_PATH} --configuration=${SWIFT_BUILD_CONFIGURATION}

SWIFT_BUILD:=${SWIFT} build ${SWIFT_FLAGS}
SWIFT_TEST:=${SWIFT} test ${SWIFT_FLAGS}
SWIFT_PACKAGE:=${SWIFT} package ${SWIFT_FLAGS}

# Name of generated xcodeproj
XCODEPROJ:=GRPC.xcodeproj

### Package and plugin build targets ###########################################

all:
	${SWIFT_BUILD}

plugins: protoc-gen-swift protoc-gen-swiftgrpc

protoc-gen-swift:
	${SWIFT_BUILD} --product protoc-gen-swift

protoc-gen-swiftgrpc:
	${SWIFT_BUILD} --product protoc-gen-swiftgrpc

interop-test-runner:
	${SWIFT_BUILD} --product InteroperabilityTestRunner

interop-backoff-test-runner:
	${SWIFT_BUILD} --product ConnectionBackoffInteropTestRunner

### Xcodeproj and LinuxMain

project: ${XCODEPROJ}

${XCODEPROJ}:
	${SWIFT_PACKAGE} generate-xcodeproj --output $@
	@-ruby fix-project-settings.rb GRPC.xcodeproj || \
		echo "Consider running 'sudo gem install xcodeproj' to automatically set correct indentation settings for the generated project."

# Generates LinuxMain.swift, only on macOS.
generate-linuxmain:
	${SWIFT_TEST} --generate-linuxmain

### Protobuf Generation ########################################################

# Generates protobufs and gRPC client and server for the Echo example
generate-echo: plugins
	protoc Sources/Examples/Echo/echo.proto \
		--proto_path=Sources/Examples/Echo \
		--plugin=${SWIFT_BUILD_PATH}/${SWIFT_BUILD_CONFIGURATION}/protoc-gen-swift \
		--plugin=${SWIFT_BUILD_PATH}/${SWIFT_BUILD_CONFIGURATION}/protoc-gen-swiftgrpc \
		--swift_out=Sources/Examples/Echo/Generated \
		--swiftgrpc_out=Sources/Examples/Echo/Generated

### Testing ####################################################################

# Normal test suite.
test:
	${SWIFT_TEST}

# Checks that linuxmain has been updated: requires macOS.
test-generate-linuxmain: generate-linuxmain
	@git diff --exit-code Tests/LinuxMain.swift Tests/*/XCTestManifests.swift > /dev/null || \
		{ echo "Generated tests are out-of-date; run 'swift test --generate-linuxmain' to update them!"; exit 1; }

# Generates code for the Echo server and client and tests them against 'golden' data.
test-plugin: plugins
	protoc Sources/Examples/Echo/echo.proto \
		--proto_path=Sources/Examples/Echo \
		--plugin=${SWIFT_BUILD_PATH}/${SWIFT_BUILD_CONFIGURATION}/protoc-gen-swift \
		--plugin=${SWIFT_BUILD_PATH}/${SWIFT_BUILD_CONFIGURATION}/protoc-gen-swiftgrpc \
		--swiftgrpc_out=/tmp
	diff -u /tmp/echo.grpc.swift Sources/Examples/Echo/Generated/echo.grpc.swift

### Misc. ######################################################################

clean:
	-rm -rf Packages
	-rm -rf ${SWIFT_BUILD_PATH}
	-rm -rf ${XCODEPROJ}
	-rm -f Package.pins Package.resolved
	-cd Examples/Google/Datastore && make clean
	-cd Examples/Google/NaturalLanguage && make clean
	-cd Examples/Google/Spanner && make clean
