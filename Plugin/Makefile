test:
	rm -f echo.client.pb.swift echo.server.pb.swift
	swift build
	cp .build/debug/protoc-gen-swiftgrpc .
	protoc echo.proto --swiftgrpc_out=.

clean :
	rm -f protoc-gen-swiftgrpc 
	rm -f swiftgrpc.log
	rm -f echo.client.pb.swift echo.server.pb.swift
	rm -rf Packages
	rm -rf .build
