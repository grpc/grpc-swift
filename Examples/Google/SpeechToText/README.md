# Speech-To-Text gRPC iOS Example

## Description

This application demonstrates Bidirectional Streaming to convert streamed audio data into text and display the Server processing live using gRPC Swift, built on top of SwiftNIO. Much of the gRPC specific logic can be found in `Sources/SpeechService.swift`.

## Technologies

* [gRPC Swift](https://github.com/grpc/grpc-swift)
* [Google Speech-To-Text API](https://cloud.google.com/speech-to-text)
* [SnapKit](https://github.com/SnapKit/SnapKit)

## Prerequisites
Please be sure to perform the preliminary steps in [Examples/Google/README](../README.md), specifically enabling "Cloud Speech-to-Text API" from Machine Learning section

## Acquiring an API Key
This project requires a Google Cloud API Key. Please [register](https://cloud.google.com/apis/docs/getting-started) and [create an API key](https://cloud.google.com/docs/authentication/api-keys) in order to consume the API.

## Project Setup
1. Clone the repository
2. Navigate to the root directory (`Examples/Google/SpeechToText`) and run `pod install`
3. Run `make protos` to pull the most recent .proto files from the googleapis repository
4. run `make generate` to leverage the `protoc` plugin to generate the Swift interfaces
    - Note: Please refer to [Getting the `protoc` Plugins](https://github.com/grpc/grpc-swift#getting-the-protoc-plugins). For this tutorial, the Makefile requires that the `protoc-gen-grpc-swift` and `protoc-gen-swift` are on the users PATH.
5. Open the `.xcworkspace`
6. Open the `Constants.swift` file and assign your generated Google Cloud API Key to the `apiKey` variable.
    - Note: Once you add the API Key, feel free to remove the forced warning/reminder on line 23.
7. Run the application!

## Helpful Links
* [Getting Started with Speech APIs](https://cloud.google.com/speech-to-text/docs/quickstart)
* [CocoaPods](https://cocoapods.org/)
* [gRPC-Swift CocoaPod](https://cocoapods.org/pods/gRPC-Swift)

NOTE: Implementation of the AudioStreamManager is based off of [Google's Example Audio Streaming](https://github.com/GoogleCloudPlatform/ios-docs-samples/blob/master/speech/Swift/Speech-gRPC-Streaming/Speech/AudioController.swift)

