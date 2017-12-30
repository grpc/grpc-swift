
default:	build

build:  clear
	swift build # This run is to build the template encoder
	.build/debug/TemplateEncoder > Sources/protoc-gen-swiftgrpc/templates.swift
	swift build # This run is to build the plugin
	cp .build/debug/protoc-gen-swiftgrpc .
	cp .build/debug/protoc-gen-swift .

test:	build
	protoc ../Examples/Echo/echo.proto --proto_path=../Examples/Echo --plugin=./protoc-gen-swiftgrpc --swiftgrpc_out=. --swift_out=.
	diff echo.rpc.swift ../Examples/Echo/Generated/echo.rpc.swift

deploy:
	cp echo.rpc.swift ../Examples/Echo/Generated/echo.rpc.swift 

clear : 
	rm -f *.pb.swift *.rpc.swift

clean : clear
	rm -rf protoc-gen-swiftgrpc Packages .build protoc-gen-swift Package.pins
	rm -rf Package.resolved
