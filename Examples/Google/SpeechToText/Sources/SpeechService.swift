//
//  SpeechService.swift
//  SpeechToText-gRPC-iOS
//
//  Created by Prickett, Jacob (J.A.) on 4/13/20.
//  Copyright © 2020 Prickett, Jacob (J.A.). All rights reserved.
//

import GRPC

final class SpeechService {

    // Generated SpeechClient for making calls
    private var client: Google_Cloud_Speech_V1_SpeechClient

    // Stream that is returned from `streamingRecognize` call
    private var call: BidirectionalStreamingCall<Google_Cloud_Speech_V1_StreamingRecognizeRequest, Google_Cloud_Speech_V1_StreamingRecognizeResponse>?

    // Track if we are streaming or not
    private var isStreaming: Bool = false

    init() {

        // Specify call options to be used for gRPC calls
        var callOptions = CallOptions()

        // API Key
        callOptions.customMetadata.add(name: "X-Goog-Api-Key",
                                       value: Constants.kAPIKey)

        // Specific Bundle Id for the API Key
        callOptions.customMetadata.add(name: "X-Ios-Bundle-Identifier",
                                       value: "com.ford.SpeechToText-gRPC-iOS")

        // Make EventLoopGroup for the specific platform (NIOTSEventLoopGroup for iOS)
        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)

        // Create connection channel with our group, host, and port
        let channel = ClientConnection
            .secure(group: group)
            .connect(host: "speech.googleapis.com", port: 443)

        // Now we have a client!
        client = Google_Cloud_Speech_V1_SpeechClient(channel: channel, defaultCallOptions: callOptions)
    }

    func stream(_ data: Data,
                completion: ((Google_Cloud_Speech_V1_StreamingRecognizeResponse) -> Void)? = nil) {
        // If we aren't already streaming
        if !isStreaming {

            // Initialize the bidirectional stream
            call = client.streamingRecognize { (response) in
                // Message received from Server, execute provided closure from caller
                completion?(response)
            }

            isStreaming = true

            // Specify audio details
            let config = Google_Cloud_Speech_V1_RecognitionConfig.with {
                $0.encoding = .linear16
                $0.sampleRateHertz = 16000
                $0.languageCode = "en-US"
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
            _ = call?.sendMessage(request)
        }

        // Stream request to send that contains the audio details
        let streamAudioDataRequest = Google_Cloud_Speech_V1_StreamingRecognizeRequest.with {
            $0.audioContent = data
        }

        // Send audio data
        _ = call?.sendMessage(streamAudioDataRequest)
    }

    func stopStreaming() {
        // Send end message to the stream
        _ = call?.sendEnd()
        isStreaming.toggle()
    }

}
