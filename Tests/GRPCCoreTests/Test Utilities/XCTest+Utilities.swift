import XCTest

func XCTAssertDescription(
  _ subject: some CustomStringConvertible,
  _ expected: String,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  XCTAssertEqual(String(describing: subject), expected, file: file, line: line)
}
