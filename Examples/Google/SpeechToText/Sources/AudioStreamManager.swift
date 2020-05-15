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

// NOTE: Implementation based off of Google's for Audio Streaming:
// https://github.com/GoogleCloudPlatform/ios-docs-samples/blob/master/speech/Swift/Speech-gRPC-Streaming/Speech/AudioController.swift

import Foundation
import AVFoundation

enum AudioStreamError: Error {
  case failedToConfigure
  case failedToFindAudioComponent
  case failedToFindMicrophoneUnit
}

protocol StreamDelegate: AnyObject {
  func processAudio(_ data: Data)
}

class AudioStreamManager {
  var microphoneUnit: AudioComponentInstance?
  weak var delegate: StreamDelegate?

  static var shared = AudioStreamManager()

  // Type used for audio unit elements. Bus 1 is input scope, element 1.
  private let bus1: AudioUnitElement = 1

  deinit {
    if let microphoneUnit = microphoneUnit {
      AudioComponentInstanceDispose(microphoneUnit)
    }
  }

  func configure() throws {
    try self.configureAudioSession()
    
    var audioComponentDescription = self.describeComponent()
    
    guard let remoteIOComponent = AudioComponentFindNext(nil, &audioComponentDescription) else {
      throw AudioStreamError.failedToFindAudioComponent
    }
    
    AudioComponentInstanceNew(remoteIOComponent, &self.microphoneUnit)
    
    try self.configureMicrophoneForInput()
    
    try self.setFormatForMicrophone()
    
    try self.setCallback()
    
    if let microphoneUnit = self.microphoneUnit {
      let status = AudioUnitInitialize(microphoneUnit)
      if status != noErr {
        throw AudioStreamError.failedToConfigure
      }
    }
  }
  
  func start() {
    guard let microphoneUnit = self.microphoneUnit else { return }
    AudioOutputUnitStart(microphoneUnit)
  }
  
  func stop() {
    guard let microphoneUnit = self.microphoneUnit else { return }
    AudioOutputUnitStop(microphoneUnit)
  }
  
  private func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record)
    try session.setPreferredIOBufferDuration(10)
  }
  
  private func describeComponent() -> AudioComponentDescription {
    var description = AudioComponentDescription()
    description.componentType = kAudioUnitType_Output
    description.componentSubType = kAudioUnitSubType_RemoteIO
    description.componentManufacturer = kAudioUnitManufacturer_Apple
    description.componentFlags = 0
    description.componentFlagsMask = 0
    return description
  }
  
  private func configureMicrophoneForInput() throws {
    guard let microphoneUnit = self.microphoneUnit else {
      throw AudioStreamError.failedToFindMicrophoneUnit
    }

    var oneFlag: UInt32 = 1
    
    let status = AudioUnitSetProperty(microphoneUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Input,
                                      self.bus1,
                                      &oneFlag,
                                      UInt32(MemoryLayout<UInt32>.size))
    if status != noErr {
      throw AudioStreamError.failedToConfigure
    }
  }
  
  private func setFormatForMicrophone() throws {
    guard let microphoneUnit = self.microphoneUnit else {
      throw AudioStreamError.failedToFindMicrophoneUnit
    }
    
    /*
     Configure Audio format to match initial message sent
     over bidirectional stream. Config and below must match.
     */
    var asbd = AudioStreamBasicDescription()
    asbd.mSampleRate = Double(Constants.sampleRate)
    asbd.mFormatID = kAudioFormatLinearPCM
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    asbd.mBytesPerPacket = 2
    asbd.mFramesPerPacket = 1
    asbd.mBytesPerFrame = 2
    asbd.mChannelsPerFrame = 1
    asbd.mBitsPerChannel = 16
    let status = AudioUnitSetProperty(microphoneUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      self.bus1,
                                      &asbd,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    if status != noErr {
      throw AudioStreamError.failedToConfigure
    }
  }
  
  private func setCallback() throws {
    guard let microphoneUnit = self.microphoneUnit else {
      throw AudioStreamError.failedToFindMicrophoneUnit
    }
    
    var callbackStruct = AURenderCallbackStruct()
    callbackStruct.inputProc = recordingCallback
    callbackStruct.inputProcRefCon = nil
    let status = AudioUnitSetProperty(microphoneUnit,
                                      kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global,
                                      self.bus1,
                                      &callbackStruct,
                                      UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    if status != noErr {
      throw AudioStreamError.failedToConfigure
    }
  }
}

func recordingCallback(
  inRefCon: UnsafeMutableRawPointer,
  ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
  inTimeStamp: UnsafePointer<AudioTimeStamp>,
  inBusNumber: UInt32,
  inNumberFrames: UInt32,
  ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
  
  var status = noErr
  
  let channelCount: UInt32 = 1
  
  var bufferList = AudioBufferList()
  bufferList.mNumberBuffers = channelCount
  let buffers = UnsafeMutableBufferPointer<AudioBuffer>(start: &bufferList.mBuffers,
                                                        count: Int(bufferList.mNumberBuffers))
  buffers[0].mNumberChannels = 1
  buffers[0].mDataByteSize = inNumberFrames * 2
  buffers[0].mData = nil
  
  // get the recorded samples
  guard let remoteIOUnit = AudioStreamManager.shared.microphoneUnit else { fatalError() }
  status = AudioUnitRender(remoteIOUnit,
                           ioActionFlags,
                           inTimeStamp,
                           inBusNumber,
                           inNumberFrames,
                           UnsafeMutablePointer<AudioBufferList>(&bufferList))
  if (status != noErr) {
    return status
  }
  
  guard let bytes = buffers[0].mData else {
    fatalError("Unable to find pointer to the buffer audio data")
  }
  
  let data = Data(bytes:  bytes, count: Int(buffers[0].mDataByteSize))
  DispatchQueue.main.async {
    AudioStreamManager.shared.delegate?.processAudio(data)
  }
  
  return noErr
}
