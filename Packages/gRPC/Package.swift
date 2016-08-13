import PackageDescription
let package = Package (
    name: "gRPC",
    dependencies: [
        .Package(url: "../CgRPC", majorVersion:1),
    ]
)
