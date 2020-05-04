// SE-0274 renames #file to #filePath so that #file may refer to the name of a file instead of
// its path. From Swift 5.3+ XCTAssert* accepts #filePath and warns when a #file is passed to it.
// These functions are used to work around that.
//
// https://github.com/apple/swift-evolution/blob/master/proposals/0274-magic-file.md

#if swift(>=5.3)
func magicFile(file: StaticString = #filePath) -> StaticString {
    return file
}
#else
func magicFile(file: StaticString = #file) -> StaticString {
    return file
}
#endif
