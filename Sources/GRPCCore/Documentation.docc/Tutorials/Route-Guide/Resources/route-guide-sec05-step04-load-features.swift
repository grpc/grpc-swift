import ArgumentParser
import Foundation

@main
struct RouteGuide: AsyncParsableCommand {
  @Flag
  var server: Bool = false

  func run() async throws {
    if self.server {
      try await self.runServer()
    }
  }

  private static func loadFeatures() throws -> [Routeguide_Feature] {
    guard let url = Bundle.module.url(forResource: "route_guide_db", withExtension: "json") else {
      throw ExitCode.failure
    }

    let data = try Data(contentsOf: url)
    return try Routeguide_Feature.array(fromJSONUTF8Bytes: data)
  }
}
