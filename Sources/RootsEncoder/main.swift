/*
 * Copyright 2017, gRPC Authors All rights reserved.
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

var s = ""
s += "/*\n"
s += " *\n"
s += " * Copyright 2017, Google Inc.\n"
s += " * All rights reserved.\n"
s += " *\n"
s += " * Redistribution and use in source and binary forms, with or without\n"
s += " * modification, are permitted provided that the following conditions are\n"
s += " * met:\n"
s += " *\n"
s += " *     * Redistributions of source code must retain the above copyright\n"
s += " * notice, this list of conditions and the following disclaimer.\n"
s += " *     * Redistributions in binary form must reproduce the above\n"
s += " * copyright notice, this list of conditions and the following disclaimer\n"
s += " * in the documentation and/or other materials provided with the\n"
s += " * distribution.\n"
s += " *     * Neither the name of Google Inc. nor the names of its\n"
s += " * contributors may be used to endorse or promote products derived from\n"
s += " * this software without specific prior written permission.\n"
s += " *\n"
s += " * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS\n"
s += " * \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT\n"
s += " * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR\n"
s += " * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT\n"
s += " * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,\n"
s += " * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT\n"
s += " * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,\n"
s += " * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY\n"
s += " * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT\n"
s += " * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE\n"
s += " * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.\n"
s += " *\n"
s += " */\n"
s += "// GENERATED: DO NOT EDIT\n"

if CommandLine.arguments.contains("test") {
  s += "//\n"
  s += "// This file contain a function that returns the contents of certificates and keys in Tests/.\n"
  s += "//\n"
  s += "import Foundation\n"
  s += "\n"

  // server.crt
  s += "let serverCertificate = "
  let certificateURL = URL(fileURLWithPath: "Tests/server.crt")
  let certificateData = try Data(contentsOf: certificateURL)
  let encodedCertificate = certificateData.base64EncodedString()
  s += "Data(base64Encoded: \"\(encodedCertificate)\", options:[])!\n"

  // server.pem
  s += "let serverKey = "
  let keyURL = URL(fileURLWithPath: "Tests/server.pem")
  let keyData = try Data(contentsOf: keyURL)
  let encodedKey = keyData.base64EncodedString()
  s += "Data(base64Encoded: \"\(encodedKey)\", options:[])!\n"

  // ca.crt
  s += "let trustCollectionCertificate = "
  let caURL = URL(fileURLWithPath: "Tests/ca.crt")
  let caData = try Data(contentsOf: caURL)
  let caEncoded = caData.base64EncodedString()
  s += "Data(base64Encoded: \"\(caEncoded)\", options:[])!\n"

  // client.crt
  s += "let clientCertificate = "
  let clientCertURL = URL(fileURLWithPath: "Tests/client.crt")
  let clientCertData = try Data(contentsOf: clientCertURL)
  let clientCertEncoded = clientCertData.base64EncodedString()
  s += "Data(base64Encoded: \"\(clientCertEncoded)\", options:[])!\n"

  // client.pem
  s += "let clientKey = "
  let clientKeyURL = URL(fileURLWithPath: "Tests/client.pem")
  let clientKeyData = try Data(contentsOf: clientKeyURL)
  let clientKeyEncoded = clientKeyData.base64EncodedString()
  s += "Data(base64Encoded: \"\(clientKeyEncoded)\", options:[])!"
} else {
  s += "//\n"
  s += "// This file contain a function that returns the default roots.pem.\n"
  s += "//\n"
  s += "import Foundation\n"
  s += "\n"

  s += "public let kRootCertificates: String = \"\"\"\n"
  let fileURL = URL(fileURLWithPath: "Assets/roots.pem")
  s += try String(contentsOf: fileURL)
  s += "\"\"\""
}
print(s)
