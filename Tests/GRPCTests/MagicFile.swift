/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
