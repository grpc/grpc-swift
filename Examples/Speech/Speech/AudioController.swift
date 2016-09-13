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
import AVFoundation

protocol AudioControllerDelegate {
  func processSampleData(_ data:Data) -> Void
}

class AudioController {
  var remoteIOUnit: AudioComponentInstance? // optional to allow it to be an inout argument
  var delegate : AudioControllerDelegate!

  static var sharedInstance = AudioController()

  deinit {
    AudioComponentInstanceDispose(remoteIOUnit!);
  }

  func prepare(specifiedSampleRate: Int) -> OSStatus {

    var status = noErr

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(AVAudioSessionCategoryRecord)
      try session.setPreferredIOBufferDuration(10)
    } catch {
      return -1
    }

    var sampleRate = session.sampleRate
    print("hardware sample rate = \(sampleRate), using specified rate = \(specifiedSampleRate)")
    sampleRate = Double(specifiedSampleRate)

    // Describe the RemoteIO unit
    var audioComponentDescription = AudioComponentDescription()
    audioComponentDescription.componentType = kAudioUnitType_Output;
    audioComponentDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    audioComponentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioComponentDescription.componentFlags = 0;
    audioComponentDescription.componentFlagsMask = 0;

    // Get the RemoteIO unit
    let remoteIOComponent = AudioComponentFindNext(nil, &audioComponentDescription)
    status = AudioComponentInstanceNew(remoteIOComponent!, &remoteIOUnit)
    if (status != noErr) {
      return status
    }

    let bus1 : AudioUnitElement = 1
    var oneFlag : UInt32 = 1

    // Configure the RemoteIO unit for input
    status = AudioUnitSetProperty(remoteIOUnit!,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  bus1,
                                  &oneFlag,
                                  UInt32(MemoryLayout<UInt32>.size));
    if (status != noErr) {
      return status
    }

    // Set format for mic input (bus 1) on RemoteIO's output scope
    var asbd = AudioStreamBasicDescription()
    asbd.mSampleRate = sampleRate
    asbd.mFormatID = kAudioFormatLinearPCM
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    asbd.mBytesPerPacket = 2
    asbd.mFramesPerPacket = 1
    asbd.mBytesPerFrame = 2
    asbd.mChannelsPerFrame = 1
    asbd.mBitsPerChannel = 16
    status = AudioUnitSetProperty(remoteIOUnit!,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  bus1,
                                  &asbd,
                                  UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    if (status != noErr) {
      return status
    }

    // Set the recording callback
    var callbackStruct = AURenderCallbackStruct()
    callbackStruct.inputProc = recordingCallback
    callbackStruct.inputProcRefCon = nil
    status = AudioUnitSetProperty(remoteIOUnit!,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  bus1,
                                  &callbackStruct,
                                  UInt32(MemoryLayout<AURenderCallbackStruct>.size));
    if (status != noErr) {
      return status
    }

    // Initialize the RemoteIO unit
    return AudioUnitInitialize(remoteIOUnit!)
  }

  func start() -> OSStatus {
    return AudioOutputUnitStart(remoteIOUnit!)
  }

  func stop() -> OSStatus {
    return AudioOutputUnitStop(remoteIOUnit!)
  }
}

func recordingCallback(
  inRefCon:UnsafeMutableRawPointer,
  ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
  inTimeStamp:UnsafePointer<AudioTimeStamp>,
  inBusNumber:UInt32,
  inNumberFrames:UInt32,
  ioData:UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

  var status = noErr

  let channelCount : UInt32 = 1

  var bufferList = AudioBufferList()
  bufferList.mNumberBuffers = channelCount
  let buffers = UnsafeMutableBufferPointer<AudioBuffer>(start: &bufferList.mBuffers,
                                                        count: Int(bufferList.mNumberBuffers))
  buffers[0].mNumberChannels = 1
  buffers[0].mDataByteSize = inNumberFrames * 2
  buffers[0].mData = nil

  // get the recorded samples
  status = AudioUnitRender(AudioController.sharedInstance.remoteIOUnit!,
                           ioActionFlags,
                           inTimeStamp,
                           inBusNumber,
                           inNumberFrames,
                           UnsafeMutablePointer<AudioBufferList>(&bufferList))
  if (status != noErr) {
    return status;
  }

  let data = Data(bytes:  buffers[0].mData!, count: Int(buffers[0].mDataByteSize))
  DispatchQueue.main.async {
    AudioController.sharedInstance.delegate.processSampleData(data)
  }

  return noErr
}
