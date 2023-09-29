//
//  File.swift
//  
//
//  Created by Stefana Dranca on 26/09/2023.
//

import GRPC
import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import XCTest

final class SerializationTests: GRPCTestCase {
    var fileDescriptorProto: Google_Protobuf_FileDescriptorProto!
    
    override func setUp() {
        super.setUp()
        let binaryFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("echo.binary-grpc.txt")
        let base64EncodedData = try! Data(contentsOf: binaryFileURL)
        let binaryData = Data(base64Encoded: base64EncodedData)!
        self.fileDescriptorProto = try! Google_Protobuf_FileDescriptorProto(serializedData: binaryData)
    }

    func testBinaryFile() throws {
        let name = self.fileDescriptorProto.name
        XCTAssertEqual(name, "echo.proto")
        
        let syntax = self.fileDescriptorProto.syntax
        XCTAssertEqual(syntax, "proto3")
        
        let package = self.fileDescriptorProto.package
        XCTAssertEqual(package, "echo")
    }
    
    func testMessages() {
        let messages = self.fileDescriptorProto.messageType
        XCTAssertEqual(messages.count, 2)
        for msg in messages {
            XCTAssert((msg.name == "EchoRequest") || (msg.name == "EchoResponse"))
            XCTAssertEqual(msg.field.count, 1)
            XCTAssertEqual(msg.field.first!.name, "text")
            XCTAssert(msg.field.first!.hasNumber)
        }
    }
        
    func testService() {
        let services = self.fileDescriptorProto.service
        XCTAssertEqual(services.count, 1)
        for method in self.fileDescriptorProto.service.first!.method {
            switch method.name {
            case "Get":
                XCTAssertEqual(method.inputType, ".echo.EchoRequest")
                XCTAssertEqual(method.outputType, ".echo.EchoResponse")
            case "Expand":
                XCTAssertEqual(method.inputType, ".echo.EchoRequest")
                XCTAssert(method.serverStreaming)
            case "Collect":
                XCTAssert(method.clientStreaming)
                XCTAssertEqual(method.outputType, ".echo.EchoResponse")
            case "Update":
                XCTAssert(method.clientStreaming)
                XCTAssert(method.serverStreaming)
            default:
                XCTFail("The method name is incorrect.")
            }
        }
    }
}
