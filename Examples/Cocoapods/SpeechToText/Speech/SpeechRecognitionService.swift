/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import SwiftGRPC

let API_KEY = "YOUR_API_KEY"
let HOST = "speech.googleapis.com"

final class Atomic<A> {
  private let queue = DispatchQueue(label: "Atomic serial queue")
  private var _value: A
  init(_ value: A) {
    self._value = value
  }
  
  var value: A {
    return queue.sync { self._value }
  }
  
  func mutate(_ transform: (inout A) -> ()) {
    queue.sync {
      transform(&self._value)
    }
  }
}

typealias SpeechRecognitionCompletionHandler = (Google_Cloud_Speech_V1_StreamingRecognizeResponse?, NSError?) -> (Void)

class SpeechRecognitionService {
  var sampleRate: Int = 16000
  private var streaming = Atomic(false)
  
  private var service: Google_Cloud_Speech_V1_SpeechServiceClient!
  private var call: Google_Cloud_Speech_V1_SpeechStreamingRecognizeCall!
  
  static let sharedInstance = SpeechRecognitionService()
  
  func streamAudioData(_ audioData: Data, completion: @escaping SpeechRecognitionCompletionHandler) {
    if (!streaming.value) {
      // if we aren't already streaming, set up a gRPC connection
      // Prepare the API client.
      service = Google_Cloud_Speech_V1_SpeechServiceClient(address: HOST)
      service.metadata = try! Metadata(["x-goog-api-key": API_KEY])
      // Call the API.
      call = try! service.streamingRecognize(metadata: service.metadata) {
        callResult in
        print("\(callResult)")
      }
      
      self.streaming.mutate {$0 = true}
      // start listening for responses
      DispatchQueue.global().async {
        while self.streaming.value {
          if let responseMessage = try? self.call.receive() {
            DispatchQueue.main.async {
              completion(responseMessage, nil)
            }
          } else {
            self.streaming.mutate {$0 = false}
            break
          }  // End of stream
        }
      }
      
      // send an initial request message to configure the service
      var recognitionConfig = Google_Cloud_Speech_V1_RecognitionConfig()
      recognitionConfig.encoding =  .linear16
      recognitionConfig.sampleRateHertz = Int32(sampleRate)
      recognitionConfig.languageCode = "en-US"
      recognitionConfig.maxAlternatives = 30
      recognitionConfig.enableWordTimeOffsets = true
      
      var streamingRecognitionConfig = Google_Cloud_Speech_V1_StreamingRecognitionConfig()
      streamingRecognitionConfig.config = recognitionConfig
      streamingRecognitionConfig.singleUtterance = false
      streamingRecognitionConfig.interimResults = true
      
      var streamingRecognizeRequest = Google_Cloud_Speech_V1_StreamingRecognizeRequest()
      streamingRecognizeRequest.streamingConfig = streamingRecognitionConfig
      
      try! call.send(streamingRecognizeRequest) { error in
        if let error = error {
          print("update send error > \(error)")
        }
      }
    }
    
    // send a request message containing the audio data
    var streamingRecognizeRequest = Google_Cloud_Speech_V1_StreamingRecognizeRequest()
    streamingRecognizeRequest.audioContent = audioData as Data
    try! call.send(streamingRecognizeRequest) { error in
      if let error = error {
        print("send error \(error)")
      }
    }
  }
  
  func stopStreaming() {
    if (!streaming.value) {
      return
    }
    try? call.closeSend()
    streaming.mutate {$0 = false}
  }
  
  func isStreaming() -> Bool {
    return streaming.value
  }
}

