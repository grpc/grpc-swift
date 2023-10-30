/*
 * Copyright 2023, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import ArgumentParser
import GRPC
import GRPCReflectionService
import NIOPosix
import SwiftProtobuf
import Logging

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@main
struct ReflectionServiceServer: AsyncParsableCommand {
    @Option(help: "The port to listen on for new connections")
    var port = 1234
    
    func run() async throws {
      let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
      defer {
        try! group.syncShutdownGracefully()
      }
      
      let helloWorldBinaryFileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Generated/helloworld.grpc.reflection.txt")
      let helloWorldBase64EncodedData = try! Data(contentsOf: helloWorldBinaryFileURL)
      let helloWorldBinaryData = Data(base64Encoded: helloWorldBase64EncodedData)!
      
      let echoBinaryFileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Generated/echo.grpc.reflection.txt")
      let echoBase64EncodedData = try! Data(contentsOf: echoBinaryFileURL)
      let echoBinaryData = Data(base64Encoded: echoBase64EncodedData)!
    
      let reflectionBinaryFileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Generated/reflection.grpc.reflection.txt")
      let reflectionBase64EncodedData = try! Data(contentsOf: reflectionBinaryFileURL)
      let reflectionBinaryData = Data(base64Encoded: reflectionBase64EncodedData)!
      
      let fileDescrptorProtos = [helloWorldBinaryData, echoBinaryData, reflectionBinaryData].map{ try! Google_Protobuf_FileDescriptorProto(serializedData: $0)}
      
      let reflectionServiceProvider = try ReflectionService(fileDescriptors: fileDescrptorProtos)
      
      // Start the server and print its address once it has started.
      let server = try await Server.insecure(group: group)
        .withServiceProviders([reflectionServiceProvider, GreeterProvider()])
        .bind(host: "localhost", port: self.port)
        .get()

      print("server started on port \(server.channel.localAddress!.port!)")
      print("server started on port \(String(describing: server.channel.localAddress?.description))")
      // Wait on the server's `onClose` future to stop the program from exiting.
      try await server.onClose.get()
    }
}
