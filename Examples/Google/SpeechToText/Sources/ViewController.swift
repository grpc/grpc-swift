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

import AVFoundation
import GRPC
import SnapKit
import UIKit

final class ViewController: UIViewController {
  private lazy var recordButton: UIButton = {
    var button = UIButton()
    button.setTitle("Record", for: .normal)
    button.setImage(UIImage(systemName: "mic"), for: .normal)
    button.backgroundColor = .darkGray
    button.layer.cornerRadius = 15
    button.clipsToBounds = true
    button.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
    return button
  }()

  private lazy var textView: UITextView = {
    var textView = UITextView()
    textView.isEditable = false
    textView.isSelectable = false
    textView.textColor = .white
    textView.textAlignment = .left
    textView.font = UIFont.systemFont(ofSize: 30)
    return textView
  }()

  private var isRecording: Bool = false {
    didSet {
      if self.isRecording {
        self.startRecording()
      } else {
        self.stopRecording()
      }
    }
  }

  private var audioData = Data()

  private let speechService: SpeechService
  private let audioStreamManager: AudioStreamManager

  init(
    speechService: SpeechService,
    audioStreamManager: AudioStreamManager
  ) {
    self.speechService = speechService
    self.audioStreamManager = audioStreamManager

    super.init(nibName: nil, bundle: nil)
  }

  convenience init() {
    self.init(
      speechService: SpeechService(),
      audioStreamManager: AudioStreamManager.shared
    )
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .black
    title = "gRPC Speech To Text"

    self.audioStreamManager.delegate = self

    let recordingSession = AVAudioSession.sharedInstance()

    recordingSession.requestRecordPermission { [weak self] allowed in
      DispatchQueue.main.async {
        if allowed {
          do {
            try self?.audioStreamManager.configure()
            self?.setupRecordingLayout()
          } catch {
            self?.setupConfigurationFailedLayout()
          }
        } else {
          self?.setupErrorLayout()
        }
      }
    }
  }

  func setupRecordingLayout() {
    view.addSubview(self.textView)
    view.addSubview(self.recordButton)

    self.textView.snp.makeConstraints { make in
      make.top.equalTo(view.safeAreaLayoutGuide.snp.topMargin)
      make.left.right.equalToSuperview()
      make.bottom.equalTo(recordButton.snp.top)
    }

    self.recordButton.snp.makeConstraints { make in
      make.height.equalTo(50)
      make.left.equalTo(40)
      make.right.equalTo(-40)
      make.bottom.equalToSuperview().inset(100)
      make.centerX.equalToSuperview()
    }
  }

  func setupErrorLayout() {
    self.textView.text = "Microphone Permissions are required in order to use this App."
    self.recordButton.isEnabled = false
  }

  func setupConfigurationFailedLayout() {
    self.textView.text = "An error occured while configuring your device for audio streaming."
    self.recordButton.isEnabled = false
  }

  @objc
  func recordTapped() {
    self.isRecording.toggle()
  }

  func startRecording() {
    self.audioData = Data()
    self.audioStreamManager.start()

    UIView.animate(withDuration: 0.02) { [weak self] in
      self?.recordButton.backgroundColor = .red
    }
  }

  func stopRecording() {
    self.audioStreamManager.stop()
    self.speechService.stopStreaming()

    UIView.animate(withDuration: 0.02) { [weak self] in
      self?.recordButton.backgroundColor = .darkGray
    }
  }
}

extension ViewController: StreamDelegate {
  func processAudio(_ data: Data) {
    self.audioData.append(data)

    // 100 ms chunk size
    let chunkSize = Int(0.1 * Constants.sampleRate * 2)

    // When the audio data gets big enough
    if self.audioData.count > chunkSize {
      // Send to server
      self.speechService.stream(self.audioData) { [weak self] response in
        guard let self = self else { return }

        DispatchQueue.main.async {
          UIView.transition(
            with: self.textView,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: {
              guard
                let results = response.results.first,
                let text = results.alternatives.first?.transcript else { return }

              if self.textView.text != text {
                self.textView.text = text
              }
            },
            completion: nil
          )
        }
      }
    }
  }
}
