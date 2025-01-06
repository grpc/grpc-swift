/*
 * Copyright 2025, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import GRPCCodeGen
import Testing

extension StructuredSwiftTests {
  @Suite("Import")
  struct Import {
    static let translator = IDLToStructuredSwiftTranslator()

    static let allAccessLevels: [SourceGenerator.Config.AccessLevel] = [
      .internal, .public, .package,
    ]

    @Test(
      "import rendering",
      arguments: allAccessLevels
    )
    func imports(accessLevel: SourceGenerator.Config.AccessLevel) throws {
      var dependencies = [Dependency]()
      dependencies.append(Dependency(module: "Foo", accessLevel: .public))
      dependencies.append(
        Dependency(
          item: .init(kind: .typealias, name: "Bar"),
          module: "Foo",
          accessLevel: .internal
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .struct, name: "Baz"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .class, name: "Bac"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .enum, name: "Bap"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .protocol, name: "Bat"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .let, name: "Baq"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .var, name: "Bag"),
          module: "Foo",
          accessLevel: .package
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .func, name: "Bak"),
          module: "Foo",
          accessLevel: .package
        )
      )

      let expected =
        """
        \(accessLevel.level) import GRPCCore
        public import Foo
        internal import typealias Foo.Bar
        package import struct Foo.Baz
        package import class Foo.Bac
        package import enum Foo.Bap
        package import protocol Foo.Bat
        package import let Foo.Baq
        package import var Foo.Bag
        package import func Foo.Bak
        """

      let imports = try StructuredSwiftTests.Import.translator.makeImports(
        dependencies: dependencies,
        accessLevel: accessLevel,
        accessLevelOnImports: true
      )

      #expect(render(imports) == expected)
    }

    @Test(
      "preconcurrency import rendering",
      arguments: allAccessLevels
    )
    func preconcurrencyImports(accessLevel: SourceGenerator.Config.AccessLevel) throws {
      var dependencies = [Dependency]()
      dependencies.append(
        Dependency(
          module: "Foo",
          preconcurrency: .required,
          accessLevel: .internal
        )
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .enum, name: "Bar"),
          module: "Foo",
          preconcurrency: .required,
          accessLevel: .internal
        )
      )
      dependencies.append(
        Dependency(
          module: "Baz",
          preconcurrency: .requiredOnOS(["Deq", "Der"]),
          accessLevel: .internal
        )
      )

      let expected =
        """
        \(accessLevel.level) import GRPCCore
        @preconcurrency internal import Foo
        @preconcurrency internal import enum Foo.Bar
        #if os(Deq) || os(Der)
        @preconcurrency internal import Baz
        #else
        internal import Baz
        #endif
        """

      let imports = try StructuredSwiftTests.Import.translator.makeImports(
        dependencies: dependencies,
        accessLevel: accessLevel,
        accessLevelOnImports: true
      )

      #expect(render(imports) == expected)
    }

    @Test(
      "SPI import rendering",
      arguments: allAccessLevels
    )
    func spiImports(accessLevel: SourceGenerator.Config.AccessLevel) throws {
      var dependencies = [Dependency]()
      dependencies.append(
        Dependency(module: "Foo", spi: "Secret", accessLevel: .internal)
      )
      dependencies.append(
        Dependency(
          item: .init(kind: .enum, name: "Bar"),
          module: "Foo",
          spi: "Secret",
          accessLevel: .internal
        )
      )

      let expected =
        """
        \(accessLevel.level) import GRPCCore
        @_spi(Secret) internal import Foo
        @_spi(Secret) internal import enum Foo.Bar
        """

      let imports = try StructuredSwiftTests.Import.translator.makeImports(
        dependencies: dependencies,
        accessLevel: accessLevel,
        accessLevelOnImports: true
      )

      #expect(render(imports) == expected)
    }

  }
}
