//
//  ChannelCrashTests.swift
//  SwiftGRPCTests
//
//  Created by Sviatoslav Bulgakov on 06/11/2018.
//

import XCTest
@testable import SwiftGRPC

class ChannelCrashProvider: Echo_EchoProvider {
    func get(request: Echo_EchoRequest, session: Echo_EchoGetSession) throws -> Echo_EchoResponse {
        return Echo_EchoResponse()
    }
    
    func collect(session: Echo_EchoCollectSession) throws -> Echo_EchoResponse? {
        return Echo_EchoResponse()
    }
    
    func update(session: Echo_EchoUpdateSession) throws -> ServerStatus? {
        return .ok
    }
    
    func expand(request: Echo_EchoRequest, session: Echo_EchoExpandSession) throws -> ServerStatus? {
        let parts = request.text.components(separatedBy: " ")
        for (i, part) in parts.enumerated() {
            usleep(500000)
            var response = Echo_EchoResponse()
            response.text = "Swift echo expand (\(i)): \(part)"
            try session.send(response) {
                if let error = $0 {
                    print("expand error: \(error)")
                }
            }
        }
        return .ok
    }
}

class ChannelCrashTests: XCTestCase {
    
    var provider = ChannelCrashProvider()
    var server: ServiceServer!
    var client: Echo_EchoServiceClient?

    func testChannelCrash() {
        server = ServiceServer(address: address, serviceProviders: [provider])
        server.start()
        
        client = Echo_EchoServiceClient(address: address, secure: false)
        client?.timeout = 4
        
        let completionHandlerExpectation = expectation(description: "completion handler called")
        
        client?.channel.subscribe { connectivityState in
            print("ConnectivityState: \(connectivityState)")
        }
        
        let request = Echo_EchoRequest(text: "foo bar baz foo bar baz")
        let call = try! client!.expand(request) { callResult in
            print("callResult.statusCode: \(callResult.statusCode)")
            completionHandlerExpectation.fulfill()
        }
        
        receive(call: call)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.client = nil
        }

        waitForExpectations(timeout: 5)
    }
    
    private func receive(call: Echo_EchoExpandCall) {
        try? call.receive { result in
            guard case .result(let u) = result, let update = u else {
                return
            }
            print("result: \(update)")
            self.receive(call: call)
        }
    }
}
