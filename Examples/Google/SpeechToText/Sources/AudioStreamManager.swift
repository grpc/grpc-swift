//
//  AudioStreamManager.swift
//  SpeechToText-gRPC-iOS
//
//  Created by Prickett, Jacob (J.A.) on 4/13/20.
//  Copyright © 2020 Prickett, Jacob (J.A.). All rights reserved.
//

/* NOTE: Implementation based off of Google's for Audio Streaming:

 https://github.com/GoogleCloudPlatform/ios-docs-samples/blob/master/speech/Swift/Speech-gRPC-Streaming/Speech/AudioController.swift

 */

import Foundation
import AVFoundation

protocol StreamDelegate: AnyObject {
    func processAudio(_ data: Data)
}

class AudioStreamManager {

    var microphoneUnit: AudioComponentInstance?
    weak var delegate: StreamDelegate?

    static var shared = AudioStreamManager()

    private let bus1: AudioUnitElement = 1
    private var oneFlag: UInt32 = 1

    deinit {
        if let microphoneUnit = microphoneUnit {
            AudioComponentInstanceDispose(microphoneUnit)
        }
    }

    func configure() {

        configureAudioSession()

        var audioComponentDescription = describeComponent()

        guard let remoteIOComponent = AudioComponentFindNext(nil, &audioComponentDescription) else {
            return
        }

        AudioComponentInstanceNew(remoteIOComponent, &microphoneUnit)

        configureMicrophoneForInput()

        setFormatForMicrophone()

        setCallback()

        if let microphoneUnit = microphoneUnit {
            AudioUnitInitialize(microphoneUnit)
        }
    }

    func start() {
        configure()
        guard let microphoneUnit = microphoneUnit else { return }
        AudioOutputUnitStart(microphoneUnit)
    }

    func stop() {
        guard let microphoneUnit = microphoneUnit else { return }
        AudioOutputUnitStop(microphoneUnit)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record)
        try? session.setPreferredIOBufferDuration(10)
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

    private func configureMicrophoneForInput() {
        guard let microphoneUnit = microphoneUnit else { return }

        AudioUnitSetProperty(microphoneUnit,
                             kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input,
                             bus1,
                             &oneFlag,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    private func setFormatForMicrophone() {
        guard let microphoneUnit = microphoneUnit else { return }

        /*
         Configure Audio format to match initial message sent
         over bidirectional stream. Config and below must match.
         */
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = Double(Constants.kSampleRate)
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        asbd.mBytesPerPacket = 2
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerFrame = 2
        asbd.mChannelsPerFrame = 1
        asbd.mBitsPerChannel = 16
        AudioUnitSetProperty(microphoneUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output,
                             bus1,
                             &asbd,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    }

    private func setCallback() {
        guard let microphoneUnit = microphoneUnit else { return }

         var callbackStruct = AURenderCallbackStruct()
         callbackStruct.inputProc = recordingCallback
         callbackStruct.inputProcRefCon = nil
         AudioUnitSetProperty(microphoneUnit,
                              kAudioOutputUnitProperty_SetInputCallback,
                              kAudioUnitScope_Global,
                              bus1,
                              &callbackStruct,
                              UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    }
}

func recordingCallback(
    inRefCon:UnsafeMutableRawPointer,
    ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp:UnsafePointer<AudioTimeStamp>,
    inBusNumber:UInt32,
    inNumberFrames:UInt32,
    ioData:UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

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

    guard let bytes = buffers[0].mData else { fatalError() }
    let data = Data(bytes:  bytes, count: Int(buffers[0].mDataByteSize))
    DispatchQueue.main.async {
        AudioStreamManager.shared.delegate?.processAudio(data)
    }

    return noErr
}
