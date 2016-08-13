import PackageDescription
let package = Package (
    name: "Client",
    dependencies: [
        .Package(url: "../gRPC", majorVersion:1),
    ]
)
