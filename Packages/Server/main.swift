import gRPC

gRPC.initialize()
print("gRPC version", gRPC.version())
do {
  let server = gRPC.Server(address:"localhost:8001")
  server.start()
  var running = true
  while(running) {
    let (_, status, requestHandler) = server.getNextRequest(timeout:600)
    if let requestHandler = requestHandler {
      print("HOST:", requestHandler.host())
      print("METHOD:", requestHandler.method())
      let initialMetadata = requestHandler.requestMetadata
      for i in 0..<initialMetadata.count() {
        print("INITIAL METADATA ->", initialMetadata.key(index:i), ":", initialMetadata.value(index:i))
      }
  
      let initialMetadataToSend = Metadata()
      initialMetadataToSend.add(key:"a", value:"Apple")
      initialMetadataToSend.add(key:"b", value:"Banana")
      initialMetadataToSend.add(key:"c", value:"Cherry")
      let (_, _, message) = requestHandler.receiveMessage(initialMetadata:initialMetadataToSend)
      print("MESSAGE", message!.string())
      if requestHandler.method() == "/quit" {
        running = false
      }
      let trailingMetadataToSend = Metadata()
      trailingMetadataToSend.add(key:"0", value:"zero")
      trailingMetadataToSend.add(key:"1", value:"one")
      trailingMetadataToSend.add(key:"2", value:"two")
      let (_, _) = requestHandler.sendResponse(message:ByteBuffer(string:"thank you very much!"),
                                               trailingMetadata:trailingMetadataToSend)
    }
  }
}
gRPC.shutdown()
print("DONE")
