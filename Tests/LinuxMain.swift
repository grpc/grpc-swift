import XCTest

import SwiftGRPCNIOTests
import SwiftGRPCTests

var tests = [XCTestCaseEntry]()
tests += SwiftGRPCNIOTests.__allTests()
tests += SwiftGRPCTests.__allTests()

XCTMain(tests)
