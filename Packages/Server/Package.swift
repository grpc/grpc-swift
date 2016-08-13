import PackageDescription
let package = Package (
    name: "Server",
    dependencies: [
        .Package(url: "../gRPC", majorVersion:1),
    ]
)
