import XCTest

import GRPCTests

var tests = [XCTestCaseEntry]()
tests += SwiftGRPCNIOTests.__allTests()

XCTMain(tests)
