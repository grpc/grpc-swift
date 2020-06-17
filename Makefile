# Which Swift to use.
SWIFT:=swift
# Where products will be built; this is the SPM default.
SWIFT_BUILD_PATH:=./.build
SWIFT_BUILD_CONFIGURATION=debug
SWIFT_FLAGS=--build-path=${SWIFT_BUILD_PATH} --configuration=${SWIFT_BUILD_CONFIGURATION}
# Force release configuration (for plugins)
SWIFT_FLAGS_RELEASE=$(patsubst --configuration=%,--configuration=release,$(SWIFT_FLAGS))

# protoc plugins.
PROTOC_GEN_SWIFT=${SWIFT_BUILD_PATH}/release/protoc-gen-swift
PROTOC_GEN_GRPC_SWIFT=${SWIFT_BUILD_PATH}/release/protoc-gen-grpc-swift

SWIFT_BUILD:=${SWIFT} build ${SWIFT_FLAGS}
SWIFT_BUILD_RELEASE:=${SWIFT} build ${SWIFT_FLAGS_RELEASE}
SWIFT_TEST:=${SWIFT} test ${SWIFT_FLAGS}
SWIFT_PACKAGE:=${SWIFT} package ${SWIFT_FLAGS}

# Name of generated xcodeproj
XCODEPROJ:=GRPC.xcodeproj

### Package and plugin build targets ###########################################

all:
	${SWIFT_BUILD}

.PHONY:
plugins: ${PROTOC_GEN_SWIFT} ${PROTOC_GEN_GRPC_SWIFT}
	cp $^ .

${PROTOC_GEN_SWIFT}: Package.resolved
	${SWIFT_BUILD_RELEASE} --product protoc-gen-swift

${PROTOC_GEN_GRPC_SWIFT}: Sources/protoc-gen-grpc-swift/*.swift
	${SWIFT_BUILD_RELEASE} --product protoc-gen-grpc-swift

interop-test-runner:
	${SWIFT_BUILD} --product GRPCInteroperabilityTests

interop-backoff-test-runner:
	${SWIFT_BUILD} --product GRPCConnectionBackoffInteropTest

### Xcodeproj and LinuxMain

.PHONY:
project: ${XCODEPROJ}

${XCODEPROJ}:
	${SWIFT_PACKAGE} generate-xcodeproj --output $@
	@-ruby scripts/fix-project-settings.rb GRPC.xcodeproj || \
		echo "Consider running 'sudo gem install xcodeproj' to automatically set correct indentation settings for the generated project."

# Generates LinuxMain.swift, only on macOS.
generate-linuxmain:
	${SWIFT_TEST} --generate-linuxmain

### Protobuf Generation ########################################################

%.pb.swift: %.proto ${PROTOC_GEN_SWIFT}
	protoc $< \
		--proto_path=$(dir $<) \
		--plugin=${PROTOC_GEN_SWIFT} \
		--swift_opt=Visibility=Public \
		--swift_out=$(dir $<)

%.grpc.swift: %.proto ${PROTOC_GEN_GRPC_SWIFT}
	protoc $< \
		--proto_path=$(dir $<) \
		--plugin=${PROTOC_GEN_GRPC_SWIFT} \
		--grpc-swift_opt=Visibility=Public \
		--grpc-swift_out=$(dir $<)

ECHO_PROTO=Sources/Examples/Echo/Model/echo.proto
ECHO_PB=$(ECHO_PROTO:.proto=.pb.swift)
ECHO_GRPC=$(ECHO_PROTO:.proto=.grpc.swift)

# For Echo we'll generate the test client as well.
${ECHO_GRPC}: ${ECHO_PROTO} ${PROTOC_GEN_GRPC_SWIFT}
	protoc $< \
		--proto_path=$(dir $<) \
		--plugin=${PROTOC_GEN_GRPC_SWIFT} \
		--grpc-swift_opt=Visibility=Public,TestClient=true \
		--grpc-swift_out=$(dir $<)

# Generates protobufs and gRPC client and server for the Echo example
.PHONY:
generate-echo: ${ECHO_PB} ${ECHO_GRPC}

HELLOWORLD_PROTO=Sources/Examples/HelloWorld/Model/helloworld.proto
HELLOWORLD_PB=$(HELLOWORLD_PROTO:.proto=.pb.swift)
HELLOWORLD_GRPC=$(HELLOWORLD_PROTO:.proto=.grpc.swift)

# Generates protobufs and gRPC client and server for the Hello World example
.PHONY:
generate-helloworld: ${HELLOWORLD_PB} ${HELLOWORLD_GRPC}

ROUTE_GUIDE_PROTO=Sources/Examples/RouteGuide/Model/route_guide.proto
ROUTE_GUIDE_PB=$(ROUTE_GUIDE_PROTO:.proto=.pb.swift)
ROUTE_GUIDE_GRPC=$(ROUTE_GUIDE_PROTO:.proto=.grpc.swift)

# Generates protobufs and gRPC client and server for the Route Guide example
.PHONY:
generate-route-guide: ${ROUTE_GUIDE_PB} ${ROUTE_GUIDE_GRPC}

### Testing ####################################################################

# Normal test suite.
.PHONY:
test:
	${SWIFT_TEST}

# Normal test suite with TSAN enabled.
.PHONY:
test-tsan:
	${SWIFT_TEST} --sanitize=thread

# Checks that linuxmain has been updated: requires macOS.
.PHONY:
test-generate-linuxmain: generate-linuxmain
	@git diff --exit-code Tests/LinuxMain.swift Tests/*/XCTestManifests.swift > /dev/null || \
		{ echo "Generated tests are out-of-date; run 'swift test --generate-linuxmain' to update them!"; exit 1; }

# Runs codegen tests.
.PHONY:
test-plugin: ${PROTOC_GEN_GRPC_SWIFT}
	PROTOC_GEN_GRPC_SWIFT=${PROTOC_GEN_GRPC_SWIFT} ./dev/codegen-tests/run-tests.sh

### Misc. ######################################################################

.PHONY:
clean:
	-rm -rf Packages
	-rm -rf ${SWIFT_BUILD_PATH}
	-rm -rf ${XCODEPROJ}
	-rm -f Package.resolved
	-cd Examples/Google/NaturalLanguage && make clean
