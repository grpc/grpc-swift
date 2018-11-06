//
//  ChannelCrashProvider.swift
//  SwiftGRPCTests
//
//  Created by Sviatoslav Bulgakov on 06/11/2018.
//

import Foundation
import SwiftGRPC

class ChannelCrashProvider: ChannelCrash_ChannelCrashProvider {
    
    func expand(request: ChannelCrash_ChannelCrashRequest, session: ChannelCrash_ChannelCrashExpandSession) throws -> ServerStatus? {
        let parts = request.text.components(separatedBy: " ")
        for (i, part) in parts.enumerated() {
            usleep(500000)
            var response = ChannelCrash_ChannelCrashResponse()
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
