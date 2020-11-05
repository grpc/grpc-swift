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
import GRPC

class UserInfoTests: GRPCTestCase {
  func testWithSubscript() {
    var userInfo = UserInfo()

    userInfo[FooKey.self] = "foo"
    assertThat(userInfo[FooKey.self], .is("foo"))

    userInfo[BarKey.self] = 42
    assertThat(userInfo[BarKey.self], .is(42))

    userInfo[FooKey.self] = nil
    assertThat(userInfo[FooKey.self], .is(.nil()))

    userInfo[BarKey.self] = nil
    assertThat(userInfo[BarKey.self], .is(.nil()))
  }

  func testWithExtensions() {
    var userInfo = UserInfo()

    userInfo.foo = "foo"
    assertThat(userInfo.foo, .is("foo"))

    userInfo.bar = 42
    assertThat(userInfo.bar, .is(42))

    userInfo.foo = nil
    assertThat(userInfo.foo, .is(.nil()))

    userInfo.bar = nil
    assertThat(userInfo.bar, .is(.nil()))
  }

  func testDescription() {
    var userInfo = UserInfo()
    assertThat(String(describing: userInfo), .is("[]"))

    // (We can't test with multiple values since ordering isn't stable.)
    userInfo.foo = "foo"
    assertThat(String(describing: userInfo), .is("[FooKey: foo]"))
  }
}

private enum FooKey: UserInfoKey {
  typealias Value = String
}

private enum BarKey: UserInfoKey {
  typealias Value = Int
}

extension UserInfo {
  fileprivate var foo: FooKey.Value? {
    get {
      return self[FooKey.self]
    }
    set {
      self[FooKey.self] = newValue
    }
  }

  fileprivate var bar: BarKey.Value? {
    get {
      return self[BarKey.self]
    }
    set {
      self[BarKey.self] = newValue
    }
  }
}
