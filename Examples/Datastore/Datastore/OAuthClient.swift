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
import Foundation

func escape(_ string : String) -> String {
  let dotsAndDashes = CharacterSet(charactersIn: "-._")
  let allowedCharacters = dotsAndDashes.union(.alphanumerics)
  if let escapedString = string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) {
    return escapedString
  } else {
    return string
  }
}

class OAuthClient {
  private var clientID : String = ""
  private var clientSecret : String = ""
  private var redirectURIs : [String] = []
  private var authURI : String = ""
  private var tokenURI : String = ""

  public var token : String? = nil

  init () {
    clientID = "885917370891-n3r74v6miibn2969estdofr68ggqa1sn.apps.googleusercontent.com"
    clientSecret = "_JDxU8iGdHYfeeER9AAEaHbn"
    redirectURIs = ["http://localhost"]
    authURI  = "https://accounts.google.com/o/oauth2/auth"
    tokenURI = "https://accounts.google.com/o/oauth2/token"
  }

  let scope = "https://www.googleapis.com/auth/datastore"

  func authCodeURL(state : String) -> URL? {
    var path = authURI
    path = path + "?response_type=" + "code"
    path = path + "&client_id=" + clientID
    path = path + "&redirect_uri=" + escape(redirectURIs[0])
    path = path + "&scope=" + escape(scope)
    path = path + "&state=" + state
    return URL(string:path)
  }

  func exchangeCode(code: String) {
    let path = tokenURI
    var body = "client_id=" + clientID
    body = body + "&client_secret=" + clientSecret
    body = body + "&code=" + escape(code)
    body = body + "&grant_type=" + "authorization_code"
    body = body + "&redirect_uri=" + escape(redirectURIs[0])

    let url = URL(string:path)!
    var request = URLRequest(url:url)
    request.httpMethod = "POST"
    request.httpBody = body.data(using:.utf8)

    let task = URLSession.shared.dataTask(with:request) { (data, response, error) in
      var json: [String:Any]!
      do {
        json = try JSONSerialization.jsonObject(with:data!, options: JSONSerialization.ReadingOptions()) as? Dictionary
      } catch {
        print(error)
      }
      self.token = json["access_token"] as! String?
    }
    task.resume()
  }
}
