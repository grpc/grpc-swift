/*
 * Copyright 2018, gRPC Authors All rights reserved.
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

import UIKit
import SwiftGRPC

let GOOGLE_API_KEY = ""

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  var service: Google_Cloud_Language_V1_LanguageServiceServiceClient!

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    // Set up an empty window.
    self.window = UIWindow(frame:UIScreen.main.bounds);
    self.window?.rootViewController = UIViewController();
    self.window?.makeKeyAndVisible();
    // Signal test start.
    signal(UIColor.yellow);
    // Prepare the API client.
    service = Google_Cloud_Language_V1_LanguageServiceServiceClient(address: "language.googleapis.com")
    service.metadata = try! Metadata(["x-goog-api-key": GOOGLE_API_KEY])
    // Call the API.
    var document = Google_Cloud_Language_V1_Document()
    document.type = .plainText
    document.content = "The Caterpillar and Alice looked at each other for some time in silence: at last the Caterpillar took the hookah out of its mouth, and addressed her in a languid, sleepy voice. `Who are you?' said the Caterpillar."
    var features = Google_Cloud_Language_V1_AnnotateTextRequest.Features()
    features.extractSyntax = true
    features.extractEntities = true
    features.extractDocumentSentiment = true
    features.extractEntitySentiment = true
    features.classifyText = true
    var request = Google_Cloud_Language_V1_AnnotateTextRequest()
    request.document = document
    request.features = features
    print("REQUEST: \(request)")
    do {
      let _ = try service.annotateText(request) {response, callresult in
        print("RESULT: \(callresult)")
        if let response = response {
          print("RESPONSE: \(response)")
          self.signal(UIColor.green);
        } else {
          self.signal(UIColor.red);
        }
      }
    } catch {
      print("ERROR: \(error)")
      signal(UIColor.red)
    }
    return true
  }

  func signal(_ c : UIColor) {
    DispatchQueue.main.async {
      self.window?.rootViewController?.view?.backgroundColor = c;
    }
  }
}

