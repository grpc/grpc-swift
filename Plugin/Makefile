
default:	build

build:  clear
	swift build --product TemplateEncoder
	.build/debug/TemplateEncoder > Sources/protoc-gen-swiftgrpc/templates.swift
	swift build --product protoc-gen-swiftgrpc
	cp .build/debug/protoc-gen-swiftgrpc .
	cp .build/debug/protoc-gen-swift .

test:	build
	protoc ../Examples/Echo/echo.proto --proto_path=../Examples/Echo --plugin=./protoc-gen-swiftgrpc --swiftgrpc_out=. --swift_out=.
	diff echo.grpc.swift ../Examples/Echo/Generated/echo.grpc.swift

deploy:
	cp echo.grpc.swift ../Examples/Echo/Generated/echo.grpc.swift 

clear : 
	rm -f *.pb.swift *.grpc.swift

clean : clear
	rm -rf protoc-gen-swiftgrpc Packages .build protoc-gen-swift Package.pins
	rm -rf Package.resolved
