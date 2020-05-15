.PHONY: log protos generate clean help

log: help

## protos              : Pull protos from Google Repository
protos:
	curl -L -O https://github.com/googleapis/googleapis/archive/master.zip
	unzip master.zip
	rm -f master.zip
	mv googleapis-master googleapis

## generate	     : Take the cloned .proto files and generate swift using the protoc plugin 
generate:
	protoc \
	googleapis/google/cloud/speech/v1/cloud_speech.proto \
	googleapis/google/rpc/status.proto \
	googleapis/google/api/client.proto \
	googleapis/google/api/annotations.proto \
	googleapis/google/api/http.proto \
	googleapis/google/longrunning/operations.proto \
	-Igoogleapis \
	--swift_out=Visibility=Public:. \
	--grpc-swift_out=Visibility=Public,Client=true,Server=false:.

	mkdir -p Sources/Generated
	find google/ -name \*.swift -exec cp {} Sources/Generated/ \;

## clean	     : Clean workspace and start from scratch (remove googleapis, generated swift, pods, etc.)
clean:
	rm -rf Pods/
	rm -rf googleapis/
	rm -rf google/
	rm Sources/Generated/*

help: Makefile
	sed -n "s/^##//p" $<
