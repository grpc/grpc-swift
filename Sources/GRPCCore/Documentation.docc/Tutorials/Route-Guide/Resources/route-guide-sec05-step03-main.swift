import ArgumentParser

@main
struct RouteGuide: AsyncParsableCommand {
  @Flag
  var server: Bool = false

  func run() async throws {
  }
}
