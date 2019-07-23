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
import UIKit
import AVFoundation

let SAMPLE_RATE = 16000

class ViewController: UIViewController, AudioControllerDelegate {
  @IBOutlet weak var textView: UITextView!
  @IBOutlet weak var button: UIButton!
  
  var audioData: Data!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    AudioController.sharedInstance.delegate = self
  }
  
  @IBAction func recordAudio(_ sender: NSObject) {
    if SpeechRecognitionService.sharedInstance.isStreaming() {
      self.stopAudio(sender)
      return
    }
    self.button.setTitle("LISTENING (tap to stop)", for: .normal)
    let audioSession = AVAudioSession.sharedInstance()
    try! audioSession.setCategory(AVAudioSession.Category.record)
    audioData = Data()
    _ = AudioController.sharedInstance.prepare(specifiedSampleRate: SAMPLE_RATE)
    SpeechRecognitionService.sharedInstance.sampleRate = SAMPLE_RATE
    _ = AudioController.sharedInstance.start()
  }
  
  @IBAction func stopAudio(_ sender: NSObject) {
    _ = AudioController.sharedInstance.stop()
    SpeechRecognitionService.sharedInstance.stopStreaming()
    self.button.setTitle("STOPPED (tap to start again)", for: .normal)
  }
  
  func processSampleData(_ data: Data) -> Void {
    audioData.append(data)
    
    // We recommend sending samples in 100ms chunks
    let chunkSize: Int /* bytes/chunk */ = Int(0.1 /* seconds/chunk */
      * Double(SAMPLE_RATE) /* samples/second */
      * 2 /* bytes/sample */);
    
    if (audioData.count > chunkSize) {
      SpeechRecognitionService.sharedInstance.streamAudioData(audioData)
      { [weak self] (response, error) in
        guard let strongSelf = self else {
          return
        }
        
        if let error = error {
          strongSelf.textView.text = error.localizedDescription
        } else if let response = response {
          print(response)
          strongSelf.textView.text = "\(response)"
          var finished = false
          for result in response.results {
            if result.isFinal {
              finished = true
            }
          }
          if finished {
            strongSelf.stopAudio(strongSelf)
          }
        }
      }
      self.audioData = Data()
    }
  }
}
