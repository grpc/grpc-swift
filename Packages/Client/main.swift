import gRPC

let address = "localhost:8001"
let host = "foo.test.google.fr"
let message = gRPC.ByteBuffer(string:"hello gRPC server!")

gRPC.initialize()
print("gRPC version", gRPC.version())

do {
  let c = gRPC.Client(address:address)
  let steps = 30
  for i in 0..<steps {
    let method = (i < steps-1) ? "/hello" : "/quit"

    let metadata = Metadata(pairs:[MetadataPair(key:"x", value:"xylophone"),
                                   MetadataPair(key:"y", value:"yu"),
                                   MetadataPair(key:"z", value:"zither")])

    let response = c.performRequest(host:host,
                                    method:method,
                                    message:message,
                                    metadata:metadata)
    print("status:", response.status)
    print("statusDetails:", response.statusDetails)
    if let message = response.message {
      print("message:", message.string())
    }

    let initialMetadata = response.initialMetadata!
    for i in 0..<initialMetadata.count() {
      print("INITIAL METADATA ->", initialMetadata.key(index:i), ":", initialMetadata.value(index:i))
    }

    let trailingMetadata = response.trailingMetadata!
    for i in 0..<trailingMetadata.count() {
      print("TRAILING METADATA ->", trailingMetadata.key(index:i), ":", trailingMetadata.value(index:i))
    }

    if (response.status != 0) {
      break
    }
  }
}
gRPC.shutdown()
print("Done")
