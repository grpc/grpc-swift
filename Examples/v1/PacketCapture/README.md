# PCAP Debugging Example

This example demonstrates how to use the `NIOWritePCAPHandler` from
[NIOExtras][swift-nio-extras] with gRPC Swift.

The example configures a client to use the `NIOWritePCAPHandler` with a file
sink so that all network traffic captured by the handler is written to a
`.pcap` file. The client makes a single bidirectional streaming RPC to an Echo
server provided by gRPC Swift.

The captured network traffic can be inspected by opening the `.pcap` with
tools like [Wireshark][wireshark] or `tcpdump`.

## Running the Example

The example relies on the Echo server from a different example. To start the
server run:

```sh
$ swift run Echo server
```

In a separate shell run:

```sh
$ swift run PacketCapture
```

The pcap file will be written to 'packet-capture-example.pcap'.

The *.pcap* file can be opened with either: [Wireshark][wireshark] or `tcpdump
-r <PCAP_FILE>`.

[swift-nio-extras]: https://github.com/apple/swift-nio-extras
[wireshark]: https://wireshark.org
