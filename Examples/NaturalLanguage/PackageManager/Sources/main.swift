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
import gRPC
import OAuth2

let scopes = ["https://www.googleapis.com/auth/cloud-language"]

if let provider = DefaultTokenProvider(scopes: scopes) {
  let sem = DispatchSemaphore(value: 0)
  try provider.withToken() {(token, error) -> Void in
    if let token = token {

      gRPC.initialize()

      guard let authToken = token.AccessToken else {
        print("ERROR: No OAuth token is available.")
        exit(-1)
      }

      let service = Google_Cloud_Language_V1_LanguageServiceService(address:"language.googleapis.com")

      service.metadata = Metadata(["authorization":"Bearer " + authToken])

      var request = Google_Cloud_Language_V1_AnnotateTextRequest()

      var document = Google_Cloud_Language_V1_Document()
      document.type = .plainText
      document.content = "The Caterpillar and Alice looked at each other for some time in silence: at last the Caterpillar took the hookah out of its mouth, and addressed her in a languid, sleepy voice. `Who are you?' said the Caterpillar."
      request.document = document

      var features = Google_Cloud_Language_V1_AnnotateTextRequest.Features()
      features.extractSyntax = true
      features.extractEntities = true
      features.extractDocumentSentiment = true
      features.extractEntitySentiment = true
      features.classifyText = true
      request.features = features

      print("\(request)")

      do {
        let result = try service.annotatetext(request)
        print("\(result)")
      } catch (let error) {
        print("ERROR: \(error)")
      }

    }
    if let error = error {
      print("ERROR \(error)")
    }
    sem.signal()
  }
  _ = sem.wait(timeout: DispatchTime.distantFuture)
} else {
  print("Unable to create default token provider.")
}


