/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

import Foundation
import GRPC
import GRPCReflectionService
import SwiftProtobuf
import XCTest

@testable import GRPCReflectionService

final class ReflectionServiceUnitTests: GRPCTestCase {
  /// Testing the fileDescriptorDataByFilename dictionary of the ReflectionServiceData object.
  func testFileDescriptorDataByFilename() throws {
    var protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)

    let registryFileDescriptorData = registry.fileDescriptorDataByFilename

    for (fileName, protoData) in registryFileDescriptorData {
      let serializedFiledescriptorData = protoData.serializedFileDescriptorProto
      let dependencyFileNames = protoData.dependencyFileNames

      guard let index = protos.firstIndex(where: { $0.name == fileName }) else {
        return XCTFail(
          """
          Could not find the file descriptor proto of \(fileName) \
          in the original file descriptor protos list.
          """
        )
      }

      let originalProto = protos[index]
      XCTAssertEqual(originalProto.name, fileName)
      XCTAssertEqual(try originalProto.serializedData(), serializedFiledescriptorData)
      XCTAssertEqual(originalProto.dependency, dependencyFileNames)

      protos.remove(at: index)
    }
    XCTAssert(protos.isEmpty)
  }

  /// Testing the serviceNames array of the ReflectionServiceData object.
  func testServiceNames() throws {
    let protos = makeProtosWithDependencies()
    let servicesNames = protos.serviceNames.sorted()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let registryServices = registry.serviceNames.sorted()
    XCTAssertEqual(registryServices, servicesNames)
  }

  /// Testing the fileNameBySymbol dictionary of the ReflectionServiceData object.
  func testFileNameBySymbol() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let registryFileNameBySymbol = registry.fileNameBySymbol

    var symbolsCount = 0

    for proto in protos {
      let qualifiedSymbolNames = proto.qualifiedSymbolNames
      symbolsCount += qualifiedSymbolNames.count
      for qualifiedSymbolName in qualifiedSymbolNames {
        XCTAssertEqual(registryFileNameBySymbol[qualifiedSymbolName], proto.name)
      }
    }

    XCTAssertEqual(symbolsCount, registryFileNameBySymbol.count)
  }

  func testFileNameBySymbolDuplicatedSymbol() throws {
    var protos = makeProtosWithDependencies()
    protos[1].messageType.append(
      Google_Protobuf_DescriptorProto.with {
        $0.name = "inputMessage2"
        $0.field = [
          Google_Protobuf_FieldDescriptorProto.with {
            $0.name = "inputField"
            $0.type = .bool
          }
        ]
      }
    )

    XCTAssertThrowsError(
      try ReflectionServiceData(fileDescriptors: protos)
    ) { error in
      XCTAssertEqual(
        error as? GRPCStatus,
        GRPCStatus(
          code: .alreadyExists,
          message:
            """
            The packagebar2.inputMessage2 symbol from bar2.proto \
            already exists in bar2.proto.
            """
        )
      )
    }
  }

  // Testing the nameOfFileContainingSymbol method for different types of symbols.

  func testNameOfFileContainingSymbolEnum() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let nameOfFileContainingSymbolResult = registry.nameOfFileContainingSymbol(
      named: "packagebar2.enumType2"
    )
    switch nameOfFileContainingSymbolResult {
    case .success(let fileName):
      XCTAssertEqual(fileName, "bar2.proto")
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testNameOfFileContainingSymbolMessage() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let nameOfFileContainingSymbolResult = registry.nameOfFileContainingSymbol(
      named: "packagebar1.inputMessage1"
    )
    switch nameOfFileContainingSymbolResult {
    case .success(let fileName):
      XCTAssertEqual(fileName, "bar1.proto")
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testNameOfFileContainingSymbolService() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let nameOfFileContainingSymbolResult = registry.nameOfFileContainingSymbol(
      named: "packagebar3.service3"
    )
    switch nameOfFileContainingSymbolResult {
    case .success(let fileName):
      XCTAssertEqual(fileName, "bar3.proto")
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testNameOfFileContainingSymbolMethod() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let nameOfFileContainingSymbolResult = registry.nameOfFileContainingSymbol(
      named: "packagebar4.service4.testMethod4"
    )
    switch nameOfFileContainingSymbolResult {
    case .success(let fileName):
      XCTAssertEqual(fileName, "bar4.proto")
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testNameOfFileContainingSymbolNonExistentSymbol() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let nameOfFileContainingSymbolResult = registry.nameOfFileContainingSymbol(
      named: "packagebar2.enumType3"
    )
    switch nameOfFileContainingSymbolResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(code: .notFound, message: "The provided symbol could not be found.")
      )
    }
  }

  // Testing the serializedFileDescriptorProto method in different cases.

  func testSerialisedFileDescriptorProtosForDependenciesOfFile() throws {
    var protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtosResult =
      registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")

    switch serializedFileDescriptorProtosResult {
    case .success(let serializedFileDescriptorProtos):
      let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
        try Google_Protobuf_FileDescriptorProto(serializedData: $0)
      }
      // Tests that the functions returns all the transitive dependencies, with their services and
      // methods, together with the initial proto, as serialized data.
      XCTAssertEqual(fileDescriptorProtos.count, 4)
      for fileDescriptorProto in fileDescriptorProtos {
        guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
          return XCTFail(
            """
            Could not find the file descriptor proto of \(fileDescriptorProto.name) \
            in the original file descriptor protos list.
            """
          )
        }

        for service in fileDescriptorProto.service {
          guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
            return XCTFail(
              """
              Could not find the \(service.name) in the service \
              list of the \(fileDescriptorProto.name) file descriptor proto.
              """
            )
          }

          let originalMethods = protos[protoIndex].service[serviceIndex].method
          for method in service.method {
            XCTAssert(originalMethods.contains(method))
          }

          for messageType in fileDescriptorProto.messageType {
            XCTAssert(protos[protoIndex].messageType.contains(messageType))
          }
        }

        protos.removeAll { $0 == fileDescriptorProto }
      }
      XCTAssert(protos.isEmpty)
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileComplexDependencyGraph() throws {
    var protos = makeProtosWithComplexDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtosResult =
      registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "foo0.proto")
    switch serializedFileDescriptorProtosResult {
    case .success(let serializedFileDescriptorProtos):
      let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
        try Google_Protobuf_FileDescriptorProto(serializedData: $0)
      }
      // Tests that the functions returns all the tranzitive dependencies, with their services and
      // methods, together with the initial proto, as serialized data.
      XCTAssertEqual(fileDescriptorProtos.count, 21)
      for fileDescriptorProto in fileDescriptorProtos {
        guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
          return XCTFail(
            """
            Could not find the file descriptor proto of \(fileDescriptorProto.name) \
            in the original file descriptor protos list.
            """
          )
        }

        for service in fileDescriptorProto.service {
          guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
            return XCTFail(
              """
              Could not find the \(service.name) in the service \
              list of the \(fileDescriptorProto.name) file descriptor proto.
              """
            )
          }

          let originalMethods = protos[protoIndex].service[serviceIndex].method
          for method in service.method {
            XCTAssert(originalMethods.contains(method))
          }

          for messageType in fileDescriptorProto.messageType {
            XCTAssert(protos[protoIndex].messageType.contains(messageType))
          }
        }

        protos.removeAll { $0 == fileDescriptorProto }
      }
      XCTAssert(protos.isEmpty)
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileDependencyLoops() throws {
    var protos = makeProtosWithDependencies()
    // Making dependencies of the "bar1.proto" to depend on "bar1.proto".
    protos[1].dependency.append("bar1.proto")
    protos[2].dependency.append("bar1.proto")
    protos[3].dependency.append("bar1.proto")
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtosResult =
      registry
      .serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")
    switch serializedFileDescriptorProtosResult {
    case .success(let serializedFileDescriptorProtos):
      let fileDescriptorProtos = try serializedFileDescriptorProtos.map {
        try Google_Protobuf_FileDescriptorProto(serializedData: $0)
      }
      // Test that we get only 4 serialized File Descriptor Protos as response.
      XCTAssertEqual(fileDescriptorProtos.count, 4)
      for fileDescriptorProto in fileDescriptorProtos {
        guard let protoIndex = protos.firstIndex(of: fileDescriptorProto) else {
          return XCTFail(
            """
            Could not find the file descriptor proto of \(fileDescriptorProto.name) \
            in the original file descriptor protos list.
            """
          )
        }

        for service in fileDescriptorProto.service {
          guard let serviceIndex = protos[protoIndex].service.firstIndex(of: service) else {
            return XCTFail(
              """
              Could not find the \(service.name) in the service \
              list of the \(fileDescriptorProto.name) file descriptor proto.
              """
            )
          }

          let originalMethods = protos[protoIndex].service[serviceIndex].method
          for method in service.method {
            XCTAssert(originalMethods.contains(method))
          }

          for messageType in fileDescriptorProto.messageType {
            XCTAssert(protos[protoIndex].messageType.contains(messageType))
          }
        }

        protos.removeAll { $0 == fileDescriptorProto }
      }
      XCTAssert(protos.isEmpty)
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileInvalidFile() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtosForDependenciesOfFileResult =
      registry.serialisedFileDescriptorProtosForDependenciesOfFile(named: "invalid.proto")

    switch serializedFileDescriptorProtosForDependenciesOfFileResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      )
    }
  }

  func testSerialisedFileDescriptorProtosForDependenciesOfFileDependencyNotProto() throws {
    var protos = makeProtosWithDependencies()
    protos[0].dependency.append("invalidDependency")
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let serializedFileDescriptorProtosForDependenciesOfFileResult =
      registry.serialisedFileDescriptorProtosForDependenciesOfFile(named: "bar1.proto")
    switch serializedFileDescriptorProtosForDependenciesOfFileResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(
          code: .notFound,
          message: "The provided file or a dependency of the provided file could not be found."
        )
      )
    }
  }

  // Testing the nameOfFileContainingExtension() method.

  func testNameOfFileContainingExtensions() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    for proto in protos {
      for `extension` in proto.extension {
        let typeName = String(`extension`.extendee.drop(while: { $0 == "." }))
        let registryFileNameResult = registry.nameOfFileContainingExtension(
          extendeeName: typeName,
          fieldNumber: `extension`.number
        )
        switch registryFileNameResult {
        case .success(let registryFileName):
          XCTAssertEqual(registryFileName, proto.name)
        case .failure(let status):
          XCTFail(
            "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
              + (status.message ?? "empty") + "."
          )
        }
      }
    }
  }

  func testNameOfFileContainingExtensionsInvalidTypeName() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let registryFileNameResult = registry.nameOfFileContainingExtension(
      extendeeName: "InvalidType",
      fieldNumber: 2
    )
    switch registryFileNameResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(
          code: .notFound,
          message: "The provided extension could not be found."
        )
      )
    }
  }

  func testNameOfFileContainingExtensionsInvalidFieldNumber() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let registryFileNameResult = registry.nameOfFileContainingExtension(
      extendeeName: protos[0].extension[0].extendee,
      fieldNumber: 9
    )
    switch registryFileNameResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(
          code: .notFound,
          message: "The provided extension could not be found."
        )
      )
    }
  }

  func testNameOfFileContainingExtensionsDuplicatedExtensions() throws {
    var protos = makeProtosWithDependencies()
    protos[0].extension.append(
      .with {
        $0.extendee = ".packagebar1.inputMessage1"
        $0.number = 2
      }
    )
    XCTAssertThrowsError(
      try ReflectionServiceData(fileDescriptors: protos)
    ) { error in
      XCTAssertEqual(
        error as? GRPCStatus,
        GRPCStatus(
          code: .alreadyExists,
          message:
            """
            The extension of the packagebar1.inputMessage1 type with the field number equal to \
            2 from \(protos[0].name) already exists in \(protos[0].name).
            """
        )
      )
    }
  }

  // Testing the extensionsFieldNumbersOfType() method.

  func testExtensionsFieldNumbersOfType() throws {
    var protos = makeProtosWithDependencies()
    protos[0].extension.append(
      .with {
        $0.extendee = ".packagebar1.inputMessage1"
        $0.number = 120
      }
    )
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let extensionsFieldNumbersOfTypeResult = registry.extensionsFieldNumbersOfType(
      named: "packagebar1.inputMessage1"
    )
    switch extensionsFieldNumbersOfTypeResult {
    case .success(let extensionsNumber):
      XCTAssertEqual(extensionsNumber, [1, 2, 3, 4, 5, 120])
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testExtensionsFieldNumbersOfTypeNoExtensionsType() throws {
    var protos = makeProtosWithDependencies()
    protos[0].messageType.append(
      Google_Protobuf_DescriptorProto.with {
        $0.name = "noExtensionMessage"
        $0.field = [
          Google_Protobuf_FieldDescriptorProto.with {
            $0.name = "noExtensionField"
            $0.type = .bool
          }
        ]
      }
    )
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let extensionsFieldNumbersOfTypeResult = registry.extensionsFieldNumbersOfType(
      named: "packagebar1.noExtensionMessage"
    )
    switch extensionsFieldNumbersOfTypeResult {
    case .success(let extensionsNumber):
      XCTAssertEqual(extensionsNumber, [])
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }

  func testExtensionsFieldNumbersOfTypeInvalidTypeName() throws {
    let protos = makeProtosWithDependencies()
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let extensionsFieldNumbersOfTypeResult = registry.extensionsFieldNumbersOfType(
      named: "packagebar1.invalidTypeMessage"
    )
    switch extensionsFieldNumbersOfTypeResult {
    case .success(_):
      XCTFail("The result should have been a failure.")
    case .failure(let status):
      XCTAssertEqual(
        status,
        GRPCStatus(
          code: .invalidArgument,
          message: "The provided type is invalid."
        )
      )
    }
  }

  func testExtensionsFieldNumbersOfTypeExtensionsInDifferentProtoFiles() throws {
    var protos = makeProtosWithDependencies()
    protos[2].extension.append(
      .with {
        $0.extendee = ".packagebar1.inputMessage1"
        $0.number = 130
      }
    )
    let registry = try ReflectionServiceData(fileDescriptors: protos)
    let extensionsFieldNumbersOfTypeResult = registry.extensionsFieldNumbersOfType(
      named: "packagebar1.inputMessage1"
    )
    switch extensionsFieldNumbersOfTypeResult {
    case .success(let extensionsNumber):
      XCTAssertEqual(extensionsNumber, [1, 2, 3, 4, 5, 130])
    case .failure(let status):
      XCTFail(
        "Faild with GRPCStatus code: " + String(status.code.rawValue) + " and message: "
          + (status.message ?? "empty") + "."
      )
    }
  }
}
