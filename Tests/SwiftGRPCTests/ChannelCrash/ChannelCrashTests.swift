//
//  ChannelCrashTests.swift
//  SwiftGRPCTests
//
//  Created by Sviatoslav Bulgakov on 06/11/2018.
//

import XCTest
@testable import SwiftGRPC

class ChannelCrashTests: XCTestCase {
    
    var provider = ChannelCrashProvider()
    var server: ServiceServer!
    var client: ChannelCrash_ChannelCrashServiceClient?

    func testChannelCrash() {
        server = ServiceServer(address: address, serviceProviders: [provider])
        server.start()
        
        client = ChannelCrash_ChannelCrashServiceClient(address: address, secure: false)
        client?.timeout = 4
        
        let completionHandlerExpectation = expectation(description: "completion handler called")
        
        client?.channel.subscribe { connectivityState in
            print("ConnectivityState: \(connectivityState)")
        }
        
        var request = ChannelCrash_ChannelCrashRequest()
        request.text = "foo bar baz foo bar baz"
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
    
    private func receive(call: ChannelCrash_ChannelCrashExpandCall) {
        try? call.receive { result in
            guard case .result(let u) = result, let update = u else {
                return
            }
            print("result: \(update)")
            self.receive(call: call)
        }
    }
}
