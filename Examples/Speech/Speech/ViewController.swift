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
  @IBOutlet weak var tableView: UITableView!

  var transcripts : [String] = []

  var audioData: NSMutableData!

  required init?(coder:NSCoder) {
    super.init(coder:coder)
    audioData = NSMutableData()
    AudioController.sharedInstance.delegate = self

    transcripts = []
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.rowHeight = 80
    let backgroundColor = UIColor(white: 0.9, alpha: 1.0)
    tableView.backgroundColor = backgroundColor
    view.backgroundColor = backgroundColor
    tableView.clipsToBounds = false
  }

  override func viewDidAppear(_ animated: Bool) {
    try! AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryRecord)

    _ = AudioController.sharedInstance.prepare(specifiedSampleRate: SAMPLE_RATE)

    SpeechRecognitionService.sharedInstance.sampleRate = SAMPLE_RATE

    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
      _ = AudioController.sharedInstance.start()

    }
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
          DispatchQueue.main.async {

            if let error = error {
              self.textView.text = error.localizedDescription
            } else if let response = response as? Message {
              var finished = false
              print("====== RECEIVED MESSAGE ======")
              response.display()
              response.forEachField("results") {(field) in
                if let alternativesField = field.message().oneField("alternatives") {
                  let alternativeMessage = alternativesField.message()
                  if let transcript = alternativeMessage.oneField("transcript") {

                    if let _ = field.message().oneField("is_final") {
                      self.transcripts.insert(transcript.string(), at:0)
                      self.tableView.insertRows(at:[IndexPath(row:0, section:0)], with: .automatic)
                      self.textView.text = ""
                      finished = true
                    } else {
                      self.textView.text = transcript.string()
                    }
                  }
                }
              }
              if finished {
                SpeechRecognitionService.sharedInstance.stopStreaming()
              }
            }
          }
      })
      self.audioData = NSMutableData()
    }
  }
}

extension ViewController : UITableViewDataSource {

  func numberOfSections(in tableView: UITableView) -> Int {
    return 1
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return transcripts.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    return TableViewCell(text:transcripts[indexPath.row])
  }

}


class TableViewCell : UITableViewCell {
  convenience init(text: String) {
    self.init(style: .default, reuseIdentifier: "cell")
    self.backgroundColor = UIColor.clear
    self.contentView.backgroundColor = UIColor.white
    if let textLabel = textLabel {
      textLabel.text = text
      textLabel.font = UIFont.systemFont(ofSize: 12)
      textLabel.numberOfLines = 0
    }
  }

  override func layoutSubviews() {
    self.contentView.frame = self.bounds.insetBy(dx: 10, dy: 6)
    if let textLabel = textLabel {
      textLabel.frame = contentView.bounds.insetBy(dx: 10, dy: 0)
    }
  }
}
