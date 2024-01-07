/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
// Sources/SwiftProtobufPluginLibrary/NamingUtils.swift - Utilities for generating names
//
// Copyright (c) 2014 - 2017 Apple Inc. and the project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information:
// https://github.com/apple/swift-protobuf/blob/main/LICENSE.txt
//

import XCTest

@testable import GRPCCodeGen

final class CasingNamerTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  func testToCamelCase() {
    // input, expectedLower, expectedUpper
    let tests: [(String, String, String)] = [
      ("", "", ""),

      ("foo", "foo", "Foo"),
      ("FOO", "foo", "Foo"),
      ("foO", "foO", "FoO"),

      ("foo_bar", "fooBar", "FooBar"),
      ("foo_bar", "fooBar", "FooBar"),
      ("foo_bAr_BaZ", "fooBArBaZ", "FooBArBaZ"),
      ("foo_bAr_BaZ", "fooBArBaZ", "FooBArBaZ"),

      ("foo1bar", "foo1Bar", "Foo1Bar"),
      ("foo2bAr3BaZ", "foo2BAr3BaZ", "Foo2BAr3BaZ"),

      ("foo_1bar", "foo1Bar", "Foo1Bar"),
      ("foo_2bAr_3BaZ", "foo2BAr3BaZ", "Foo2BAr3BaZ"),
      ("_0foo_1bar", "_0Foo1Bar", "_0Foo1Bar"),
      ("_0foo_2bAr_3BaZ", "_0Foo2BAr3BaZ", "_0Foo2BAr3BaZ"),

      ("url", "url", "URL"),
      ("http", "http", "HTTP"),
      ("https", "https", "HTTPS"),
      ("id", "id", "ID"),

      ("the_url", "theURL", "TheURL"),
      ("use_http", "useHTTP", "UseHTTP"),
      ("use_https", "useHTTPS", "UseHTTPS"),
      ("request_id", "requestID", "RequestID"),

      ("url_number", "urlNumber", "URLNumber"),
      ("http_needed", "httpNeeded", "HTTPNeeded"),
      ("https_needed", "httpsNeeded", "HTTPSNeeded"),
      ("id_number", "idNumber", "IDNumber"),

      ("is_url_number", "isURLNumber", "IsURLNumber"),
      ("is_http_needed", "isHTTPNeeded", "IsHTTPNeeded"),
      ("is_https_needed", "isHTTPSNeeded", "IsHTTPSNeeded"),
      ("the_id_number", "theIDNumber", "TheIDNumber"),

      ("url_foo_http_id", "urlFooHTTPID", "URLFooHTTPID"),

      ("göß", "göß", "Göß"),
      ("göo", "göO", "GöO"),
      ("gö_o", "göO", "GöO"),
      ("g_🎉_o", "g🎉O", "G🎉O"),
      ("g🎉o", "g🎉O", "G🎉O"),

      ("m\u{AB}n", "m_u171N", "M_u171N"),
      ("m\u{AB}_n", "m_u171N", "M_u171N"),
      ("m_\u{AB}_n", "m_u171N", "M_u171N"),

      ("urlTest", "urlTest", "URLTest"),
      ("ABService", "abservice", "Abservice"),
    ]

    for (input, expectedLower, expectedUppper) in tests {
      XCTAssertEqual(CasingNamer.toLowerCamelCase(input), expectedLower)
      XCTAssertEqual(CasingNamer.toUpperCamelCase(input), expectedUppper)
    }
  }
}
