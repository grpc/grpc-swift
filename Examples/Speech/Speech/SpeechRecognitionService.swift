//
// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import Foundation

let API_KEY : String = "AIzaSyAZSuTl9SvDuuU2jc1Ajw5WEoa_O6ttlCo"
let HOST = "speech.googleapis.com:443"

typealias SpeechRecognitionCompletionHandler = (Any?, NSError?) -> (Void)

class SpeechRecognitionService {
  var sampleRate: Int = 16000
  private var streaming = false

  var client: Client!
  var call: Call!
  var fileDescriptorSet : FileDescriptorSet

  static let sharedInstance = SpeechRecognitionService()

  private init() {
    fileDescriptorSet = FileDescriptorSet(filename: "speech.out")
  }

  func streamAudioData(_ audioData: NSData, completion: SpeechRecognitionCompletionHandler) {

    if (!streaming) {
      // if we aren't already streaming, set up a gRPC connection
      client = Client(address:HOST, certificates: nil, host: nil)
      call = client.createCall(host: HOST,
                               method: "/google.cloud.speech.v1beta1.Speech/StreamingRecognize",
                               timeout: 60.0)

      let metadata = Metadata(["x-goog-api-key":API_KEY,
                               "x-ios-bundle-identifier":Bundle.main.bundleIdentifier!])
      call.start(metadata:metadata)

      let recognitionConfig = fileDescriptorSet.createMessage("RecognitionConfig")!
      recognitionConfig.addField("encoding") {(field) in field.setInt(1)} // LINEAR16
      recognitionConfig.addField("sample_rate") {(field) in field.setInt(self.sampleRate)}
      recognitionConfig.addField("language_code") {(field) in field.setString("en-US")}
      recognitionConfig.addField("max_alternatives") {(field) in field.setInt(30)}

      let streamingRecognitionConfig = fileDescriptorSet.createMessage("StreamingRecognitionConfig")!
      streamingRecognitionConfig.addField("config") {(field) in field.setMessage(recognitionConfig)}
      streamingRecognitionConfig.addField("single_utterance") {(field) in field.setBool(false)}
      streamingRecognitionConfig.addField("interim_results") {(field) in field.setBool(true)}

      let streamingRecognizeRequest = fileDescriptorSet.createMessage("StreamingRecognizeRequest")!
      streamingRecognizeRequest.addField("streaming_config")
      {(field) in field.setMessage (streamingRecognitionConfig)}

      streamingRecognizeRequest.display()
      let messageData = streamingRecognizeRequest.data()
      call.sendMessage(data:messageData)
      streaming = true

      self.receiveMessage()
    }

    let streamingRecognizeRequest = fileDescriptorSet.createMessage("StreamingRecognizeRequest")!
    streamingRecognizeRequest.addField("audio_content") {(field) in
      field.setData(audioData as Data)
    }
    let messageData = streamingRecognizeRequest.data()
    call.sendMessage(data:messageData)

  }

  func receiveMessage() {
    call.receiveMessage() {(data) in
      if let data = data {
        if let responseMessage = self.fileDescriptorSet.readMessage(
          "StreamingRecognizeResponse",
          data:data) {
          responseMessage.display()
        }
      }
      self.receiveMessage()
    }
  }

  func stopStreaming() {
    if (!streaming) {
      return
    }
    // writer.finishWithError(nil)
    streaming = false
  }
  
  func isStreaming() -> Bool {
    return streaming
  }
  
}

