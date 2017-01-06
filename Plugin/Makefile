
all:	test

build:
	rm -f echo.client.pb.swift echo.server.pb.swift
	swift build
	cp .build/debug/protoc-gen-swiftgrpc .


test:	build
	protoc echo.proto --swiftgrpc_out=.
	diff echo.client.pb.swift ../Examples/Echo/Swift/Echo/echo.client.pb.swift
	diff echo.server.pb.swift ../Examples/Echo/Swift/Echo/echo.server.pb.swift

deploy:
	cp echo.client.pb.swift ../Examples/Echo/Swift/Echo/echo.client.pb.swift 
	cp echo.server.pb.swift ../Examples/Echo/Swift/Echo/echo.server.pb.swift 

clean :
	rm -f protoc-gen-swiftgrpc 
	rm -f swiftgrpc.log
	rm -f echo.client.pb.swift echo.server.pb.swift
	rm -rf Packages
	rm -rf .build
