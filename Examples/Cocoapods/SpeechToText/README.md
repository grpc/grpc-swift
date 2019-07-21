# Cloud Speech-to-Text Streaming gRPC Swift Sample

This app demonstrates how to make streaming gRPC connections to the [Google Cloud Speech-to-Text API](https://cloud.google.com/speech-to-text/) to recognize speech in recorded audio.

## Prerequisites
- An API key for the Cloud Speech-to-Text API 
- An OSX machine or emulator
- [Xcode 10][xcode] or later
- [Cocoapods][cocoapods] version 1.0 or later

## Quickstart
- Clone this repo and `cd` into this directory.
- Run `./COMPILE-PROTOS.sh` to generate the Protocol Buffer and gRPC support files. Note that this requires protoc and the protoc-gen-swift and protoc-gen-swiftgrpc plugins. You can get the plugins by running `swift build` in the root of the grpc-swift repository.
- Run `./INSTALL-COCOAPODS.sh` to download and set up all Cocoapods dependencies.
- In `Speech/SpeechRecognitionService.swift`, replace `YOUR_API_KEY` with the API key obtained above.
- Build and run the app.

## Running the app

- As with all Google Cloud APIs, every call to the Speech-to-Text API must be associated
  with a project within the [Google Cloud Console][cloud-console] that has the
  Speech-to-Text API enabled. This is described in more detail in the [getting started
  doc][getting-started], but in brief:
  - Create a project (or use an existing one) in the [Cloud
    Console][cloud-console]
  - [Enable billing][billing] and the [Speech API][enable-speech].
  - Create an [API key][api-key], and save this for later.

- `cd` into this directory in the repository you just cloned, and run the command `pod install` to prepare all Cocoapods-related dependencies.

- `open Speech.xcworkspace` to open this project in Xcode. Since we are using Cocoapods, be sure to open the workspace and not Speech.xcodeproj.

- In Xcode's Project Navigator, open the `SpeechRecognitionService.swift` file within the `Speech` directory.

- Find the line where the `API_KEY` is set. Replace the string value with the API key obtained from the Cloud console above. This key is the credential used to authenticate all requests to the Speech API. Calls to the API are thus associated with the project you created above, for access and billing purposes.

- You are now ready to build and run the project. In Xcode you can do this by clicking the 'Play' button in the top left. This will launch the app on the simulator or on the device you've selected. Be sure that the 'Speech' target is selected in the popup near the top left of the Xcode window. 

- Tap the `START` button. This uses a custom AudioController class to capture audio in an in-memory instance of NSMutableData. When this data reaches a certain size, it is sent to the SpeechRecognitionService class, which streams it to the speech recognition service. Packets are streamed as instances of the RecognizeRequest object, and the first RecognizeRequest object sent also includes configuration information in an instance of InitialRecognizeRequest. As it runs, the AudioController logs the number of samples and average sample magnitude for each packet that it captures.

- Say a few words and wait for the display to update when your speech is recognized.

- Normally your connection will close when speech is recognized. to stop early, press the top button again.

[getting-started]: https://cloud.google.com/speech-to-text/docs/quickstart
[cloud-console]: https://console.cloud.google.com
[git]: https://git-scm.com/
[xcode]: https://developer.apple.com/xcode/
[billing]: https://console.cloud.google.com/billing?project=_
[enable-speech]: https://console.cloud.google.com/apis/api/speech.googleapis.com/overview?project=_
[api-key]: https://console.cloud.google.com/apis/credentials?project=_
[cocoapods]: https://cocoapods.org/
