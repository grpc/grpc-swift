
default:	build

build:  clear
	swift build # This run is to build the template encoder
	.build/debug/TemplateEncoder > Sources/protoc-gen-swiftgrpc/templates.swift
	swift build # This run is to build the plugin
	cp .build/debug/protoc-gen-swiftgrpc .
	cp .build/debug/protoc-gen-swift .

test:	build
	protoc ../Examples/Echo/echo.proto --proto_path=../Examples/Echo --plugin=./protoc-gen-swiftgrpc --swiftgrpc_out=. --swift_out=.
	diff echo0.client.pb.swift ../Examples/Echo/Generated/echo0.client.pb.swift
	diff echo.server.pb.swift ../Examples/Echo/Generated/echo.server.pb.swift

deploy:
	cp echo0.client.pb.swift ../Examples/Echo/Generated/echo0.client.pb.swift 
	cp echo.server.pb.swift ../Examples/Echo/Generated/echo.server.pb.swift 

clear : 
	rm -f echo.pb.swift echo0.client.pb.swift echo.server.pb.swift swiftgrpc.log

clean : clear
	rm -rf protoc-gen-swiftgrpc Packages .build protoc-gen-swift Package.pins
	rm -rf Package.resolved
