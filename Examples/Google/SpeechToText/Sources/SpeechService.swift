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

typealias Request = Google_Cloud_Speech_V1_StreamingRecognizeRequest
typealias Response = Google_Cloud_Speech_V1_StreamingRecognizeResponse
typealias StreamingRecognizeCall = BidirectionalStreamingCall

final class SpeechService {
  // Track whether we are currently streaming or not
  enum State {
    case idle
    case streaming(StreamingRecognizeCall<Request, Response>)
  }

  // Generated SpeechClient for making calls
  private var client: Google_Cloud_Speech_V1_SpeechClient

  // Track if we are streaming or not
  private var state: State = .idle

  init() {
    precondition(!Constants.apiKey.isEmpty, "Please refer to the README on how to configure your API Key properly.")

    // Make EventLoopGroup for the specific platform (NIOTSEventLoopGroup for iOS)
    // see https://github.com/grpc/grpc-swift/blob/main/docs/apple-platforms.md for more details
    let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)

    // Create a connection secured with TLS to Google's speech service running on our `EventLoopGroup`
    let channel = ClientConnection
      .secure(group: group)
      .connect(host: "speech.googleapis.com", port: 443)

    // Specify call options to be used for gRPC calls
    let callOptions = CallOptions(customMetadata: [
      "x-goog-api-key": Constants.apiKey
    ])

    // Now we have a client!
    self.client = Google_Cloud_Speech_V1_SpeechClient(channel: channel, defaultCallOptions: callOptions)
  }

  func stream(_ data: Data,
              completion: ((Google_Cloud_Speech_V1_StreamingRecognizeResponse) -> Void)? = nil) {
    switch self.state {
    case .idle:
      // Initialize the bidirectional stream
      let call = self.client.streamingRecognize { response in
        // Message received from Server, execute provided closure from caller
        completion?(response)
      }

      self.state = .streaming(call)

      // Specify audio details
      let config = Google_Cloud_Speech_V1_RecognitionConfig.with {
        $0.encoding = .linear16
        $0.sampleRateHertz = Int32(Constants.sampleRate)
        $0.languageCode = "en-US"
        $0.enableAutomaticPunctuation = true
        $0.metadata = Google_Cloud_Speech_V1_RecognitionMetadata.with {
          $0.interactionType = .dictation
          $0.microphoneDistance = .nearfield
          $0.recordingDeviceType = .smartphone
        }
      }

      // Create streaming request
      let request = Google_Cloud_Speech_V1_StreamingRecognizeRequest.with {
        $0.streamingConfig = Google_Cloud_Speech_V1_StreamingRecognitionConfig.with {
          $0.config = config
        }
      }

      // Send first message consisting of the streaming request details
      call.sendMessage(request, promise: nil)

      // Stream request to send that contains the audio details
      let streamAudioDataRequest = Google_Cloud_Speech_V1_StreamingRecognizeRequest.with {
        $0.audioContent = data
      }

      // Send audio data
      call.sendMessage(streamAudioDataRequest, promise: nil)

    case .streaming(let call):
      // Stream request to send that contains the audio details
      let streamAudioDataRequest = Google_Cloud_Speech_V1_StreamingRecognizeRequest.with {
        $0.audioContent = data
      }

      // Send audio data
      call.sendMessage(streamAudioDataRequest, promise: nil)
    }
  }

  func stopStreaming() {
    // Send end message to the stream
    switch self.state {
    case .idle:
      return
    case .streaming(let stream):
      stream.sendEnd(promise: nil)
      self.state = .idle
    }
  }
}
