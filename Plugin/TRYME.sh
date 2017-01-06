#!/bin/sh

rm echo.client.pb.swift echo.server.pb.swift
swift build
cp .build/debug/protoc-gen-swiftgrpc .
protoc echo.proto --swiftgrpc_out=.
