/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
import Cocoa
import WebKit

class WebViewWindowController : NSWindowController {
  @IBOutlet var webView : WebView!
  var url : URL?

  var completion: ((String) -> Void)?

  override func awakeFromNib() {
    super.awakeFromNib()
    self.webView.resourceLoadDelegate = self
    if let url = url {
      self.webView.mainFrame.load(URLRequest(url:url))
    }
  }

}

extension WebViewWindowController : WebResourceLoadDelegate {

  func webView(_ sender: WebView!,
               resource identifier: Any!,
               willSend request: URLRequest!,
               redirectResponse: URLResponse!,
               from dataSource: WebDataSource!) -> URLRequest! {

    print(request)

    if (request.url!.absoluteString.hasPrefix("http://localhost")) {

      print("incoming \(request.url!.absoluteString)")
      let keyVals = request.url!.getKeyVals()!
      let code = keyVals["code"]!

      print("Got it! \(code)")

      if let completion = completion {
        completion(code)
      }
      window!.close()
      return nil
    }

    return request
  }
}

extension URL {
  func getKeyVals() -> Dictionary<String, String>? {
    var results = [String:String]()
    let keyValues = self.query?.components(separatedBy: "&")
    if keyValues!.count > 0 {
      for pair in keyValues! {
        let kv = pair.components(separatedBy:"=")
        if kv.count > 1 {
          results.updateValue(kv[1], forKey: kv[0])
        }
      }
    }
    return results
  }
}
