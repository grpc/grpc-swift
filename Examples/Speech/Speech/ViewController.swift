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
import UIKit
import AVFoundation

let SAMPLE_RATE = 16000

class ViewController : UIViewController, AudioControllerDelegate {
  @IBOutlet weak var textView: UITextView!
  var audioData: NSMutableData!

  override func viewDidLoad() {
    super.viewDidLoad()
    AudioController.sharedInstance.delegate = self
  }

  @IBAction func recordAudio(_ sender: NSObject) {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(AVAudioSessionCategoryRecord)
    } catch {

    }
    audioData = NSMutableData()
    _ = AudioController.sharedInstance.prepare(specifiedSampleRate: SAMPLE_RATE)
    SpeechRecognitionService.sharedInstance.sampleRate = SAMPLE_RATE
    _ = AudioController.sharedInstance.start()
  }

  @IBAction func stopAudio(_ sender: NSObject) {
    _ = AudioController.sharedInstance.stop()
    SpeechRecognitionService.sharedInstance.stopStreaming()
  }

  func processSampleData(_ data: Data) -> Void {
    audioData.append(data)

    // We recommend sending samples in 100ms chunks
    let chunkSize : Int /* bytes/chunk */ = Int(0.1 /* seconds/chunk */
      * Double(SAMPLE_RATE) /* samples/second */
      * 2 /* bytes/sample */);

    if (audioData.length > chunkSize) {
      SpeechRecognitionService.sharedInstance.streamAudioData(audioData,
                                                              completion:
        { (response, error) in
          if let error = error {
            self.textView.text = error.localizedDescription
          } else if let response = response {
            var finished = false
            print(response)
            /*
            for result in response.resultsArray! {
              if let result = result as? StreamingRecognitionResult {
                if result.isFinal {
                  finished = true
                }
              }
            }
            self.textView.text = response.description
            if finished {
              self.stopAudio(self)
            }
 */
          }
      })
      self.audioData = NSMutableData()
    }
  }
}
