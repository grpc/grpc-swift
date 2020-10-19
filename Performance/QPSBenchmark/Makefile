# Which Swift to use.
SWIFT:=swift
# Where products will be built; this is the SPM default.
GRPC_SWIFT_PATH:=../..
SWIFT_BUILD_PATH:=./.build
SWIFT_BUILD_CONFIGURATION=release
SWIFT_FLAGS=--build-path=${SWIFT_BUILD_PATH} --configuration=${SWIFT_BUILD_CONFIGURATION}

# protoc plugins.
PROTOC_GEN_SWIFT=${GRPC_SWIFT_PATH}/${SWIFT_BUILD_PATH}/release/protoc-gen-swift
PROTOC_GEN_GRPC_SWIFT=${GRPC_SWIFT_PATH}/${SWIFT_BUILD_PATH}/release/protoc-gen-grpc-swift

SWIFT_BUILD:=${SWIFT} build ${SWIFT_FLAGS}
SWIFT_BUILD_RELEASE:=${SWIFT} build ${SWIFT_FLAGS_RELEASE}

### Package and plugin build targets ###########################################

all:
	${SWIFT_BUILD}

${PROTOC_GEN_SWIFT}: ${GRPC_SWIFT_PATH}/Package.resolved
	${SWIFT_BUILD_RELEASE} --product protoc-gen-swift --package-path ${GRPC_SWIFT_PATH}

${PROTOC_GEN_GRPC_SWIFT}: ${GRPC_SWIFT_PATH}/Sources/protoc-gen-grpc-swift/*.swift
	${SWIFT_BUILD_RELEASE} --product protoc-gen-grpc-swift --package-path ${GRPC_SWIFT_PATH}

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

QBS_PROTO=Sources/QPSBenchmark/Model/benchmark_service.proto \
          Sources/QPSBenchmark/Model/payloads.proto \
          Sources/QPSBenchmark/Model/control.proto \
          Sources/QPSBenchmark/Model/stats.proto \
          Sources/QPSBenchmark/Model/core_stats.proto \
          Sources/QPSBenchmark/Model/worker_service.proto \
          Sources/QPSBenchmark/Model/messages.proto
QBS_PB=$(QBS_PROTO:.proto=.pb.swift)
QBS_GRPC=$(QBS_PROTO:.proto=.grpc.swift)

# Generate the protobufs for the QPS benchmarking worker.
.PHONY:
generate-qps-worker: ${QBS_PB} ${QBS_GRPC}

### Misc. ######################################################################

.PHONY:
clean:
	-rm -rf Packages
	-rm -rf ${SWIFT_BUILD_PATH}
	-rm -f Package.resolved
