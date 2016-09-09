//
//  StickyServer.swift
//  StickyNotes
//
//  Created by Tim Burks on 9/8/16.
//  Copyright © 2016 Google. All rights reserved.
//

import Foundation
import gRPC
import QuickProto

class StickyServer {

  private var address : String

  init(address: String) {
    gRPC.initialize()
    self.address = address
  }

  func log(_ message: String) {
    print(message)
  }

  func start() {
    let fileDescriptorSet = FileDescriptorSet(filename:"stickynote.out")

    DispatchQueue.global().async {
      self.log("Server Starting")
      self.log("GRPC version " + gRPC.version())

      let server = gRPC.Server(address:self.address)
      server.run {(requestHandler) in

        self.log("Received request to " + requestHandler.host()
          + " calling " + requestHandler.method()
          + " from " + requestHandler.caller())
        let initialMetadata = requestHandler.requestMetadata
        for i in 0..<initialMetadata.count() {
          self.log("Received initial metadata -> " + initialMetadata.key(index:i) + ":" + initialMetadata.value(index:i))
        }

        if (requestHandler.method() == "/messagepb.StickyNote/Get") {
          requestHandler.receiveMessage(initialMetadata:Metadata())
          {(requestData) in
            if let requestData = requestData,
              let requestMessage =
              fileDescriptorSet.readMessage(name:"StickyNoteRequest",
                                            proto:requestData) {
              requestMessage.forOneField(name:"message") {(field) in
                let imageData = self.drawImage(message: field.string())

                let replyMessage = fileDescriptorSet.createMessage(name:"StickyNoteResponse")!
                replyMessage.addField(name:"image", value:imageData)
                requestHandler.sendResponse(message:replyMessage.serialize(),
                                            trailingMetadata:Metadata())
              }
            }
          }
        }
      }
    }
  }

  /// draw a stickynote
  func drawImage(message: String) -> NSData {
    let image = NSImage.init(size: NSSize.init(width: 400, height: 400),
                             flipped: false,
                             drawingHandler: { (rect) -> Bool in
                              NSColor.yellow.set()
                              NSRectFill(rect)
                              NSColor.black.set()
                              let string = NSString(string:message)
                              let trialS = CGFloat(300.0)
                              let trialFont = NSFont.userFont(ofSize:trialS)!
                              let trialAttributes = [NSFontAttributeName: trialFont]
                              let trialSize = string.size(withAttributes: trialAttributes)
                              let s = trialS * 300 / trialSize.width;
                              let font = NSFont.userFont(ofSize:s)!
                              let attributes = [NSFontAttributeName: font]
                              let size = string.size(withAttributes: attributes)
                              let x = rect.origin.x + 0.5*(rect.size.width - size.width)
                              let y = rect.origin.y + 0.5*(rect.size.height - size.height)
                              let r = NSMakeRect(x, y, size.width, size.height)
                              string.draw(in: r, withAttributes:attributes)
                              return true})
    let imgData: Data! = image.tiffRepresentation!
    let bitmap: NSBitmapImageRep! = NSBitmapImageRep(data: imgData)
    let pngImage = bitmap!.representation(using:NSBitmapImageFileType.PNG, properties:[:])
    return NSData(data:pngImage!)
  }

}
