/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
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
          self.log("Received initial metadata -> " + initialMetadata.key(index:i)
            + ":" + initialMetadata.value(index:i))
        }

        if (requestHandler.method() == "/messagepb.StickyNote/Get") {
          requestHandler.receiveMessage(initialMetadata:Metadata())
          {(requestData) in
            if let requestData = requestData,
              let requestMessage =
              fileDescriptorSet.readMessage("StickyNoteRequest", data: requestData) {
              requestMessage.forOneField("message") {(field) in
                let imageData = self.drawImage(message: field.string())

                let replyMessage = fileDescriptorSet.makeMessage("StickyNoteResponse")!
                replyMessage.addField("image", value:imageData)
                requestHandler.sendResponse(message:replyMessage.data(),
                                            trailingMetadata:Metadata())
              }
            }
          }
        }
      }
    }
  }

  /// draw a stickynote
  func drawImage(message: String) -> Data? {
    let image = NSImage.init(size: NSSize.init(width: 400, height: 400),
                             flipped: false,
                             drawingHandler:
      { (rect) -> Bool in
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
    return pngImage
  }
}
