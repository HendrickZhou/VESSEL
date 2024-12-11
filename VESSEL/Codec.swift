//
//  Codec.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/19/24.
//

import Foundation
import AudioToolbox
import AVFoundation
import c_qoa

class PCMSpeech16 {
    public var samples: [Int16]
    public var channelNum: UInt8  // up to 255 channels
    public var sampleRate: UInt16 // up to 65k, enough for full range speech signal
    
    init(samples: [Int16], channelNum: UInt8, sampleRate: UInt16) {
        self.samples = samples
        self.channelNum = channelNum
        self.sampleRate = sampleRate
    }
    
    public var sampleNum : Int {
        return samples.count
    }
    
    public var duration: Double {
        return Double(sampleNum) / Double(UInt16(channelNum) * sampleRate)
    }
}

class QOACodec {
    func decode_by_frame(frame_data : Data) -> PCMSpeech16? {
        //c_qoa.qoa_decode_frame(<#T##bytes: UnsafePointer<UInt8>!##UnsafePointer<UInt8>!#>, <#T##size: UInt32##UInt32#>, <#T##qoa: UnsafeMutablePointer<qoa_desc>!##UnsafeMutablePointer<qoa_desc>!#>, <#T##sample_data: UnsafeMutablePointer<Int16>!##UnsafeMutablePointer<Int16>!#>, <#T##frame_len: UnsafeMutablePointer<UInt32>!##UnsafeMutablePointer<UInt32>!#>)
        return nil
    }
}


func inputDataProvider(
    inAudioConverter: AudioConverterRef,
    ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
    ioData: UnsafeMutablePointer<AudioBufferList>,
    outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = inUserData else {
        return kAudio_ParamError
    }
    
    let context = userData.assumingMemoryBound(to: MP3Codec.InputDataContext.self).pointee
    ioData.pointee = context.inputBufferList
    ioNumberDataPackets.pointee = context.inputDataPacketCount
    return noErr
}

class MP3Codec {
    private var audioConverter: AudioConverterRef?
    private var maxBitrate: UInt32
    private var frameSize: Int
    private let sampleRate: Int
    private let channels: Int

    // Initializes the MP3 codec with initial configurations.
    // - Parameters:
    //   - maxBitrate: Initial maximum bitrate in bits per second.
    //   - frameSize: Initial frame size (number of PCM samples per frame).
    //   - sampleRate: Audio sample rate in Hz.
    //   - channels: Number of audio channels.
    init(maxBitrate: UInt32 = 128_000, frameSize: Int = 1152, sampleRate: Int = 44100, channels: Int = 2) {
        self.maxBitrate = maxBitrate
        self.frameSize = frameSize
        self.sampleRate = sampleRate
        self.channels = channels
    }

    // Encodes PCM data into MP3 format with dynamic adjustment.
    // - Parameters:
    //   - pcmData: The PCM data to encode.
    //   - networkFeedback: A dictionary containing network feedback (e.g., "bandwidth", "latency").
    // - Returns: Encoded MP3 data as `Data`, or `nil` if encoding fails.
    func encode(pcmData: PCMSpeech16, networkFeedback: [String: Double]) -> Data? {
        // Adjust compression settings based on feedback
        adjustSettings(feedback: networkFeedback)

        // Configure the input and output audio formats
        var inputFormat = createPCMFormat(sampleRate: sampleRate, channels: channels)
        var outputFormat = createMP3Format(sampleRate: sampleRate, channels: channels)

        // Create the Audio Converter
        if audioConverter == nil {
            var converter: AudioConverterRef?
            let status = AudioConverterNew(&inputFormat, &outputFormat, &converter)
            guard status == noErr, let createdConverter = converter else {
                print("Failed to create Audio Converter: \(status)")
                return nil
            }
            self.audioConverter = createdConverter
        }

        // Configure VBR mode
        setVBRMode()

        // Perform the encoding
        return encodePCMToMP3(pcmData: pcmData)
    }

    // Adjusts encoding settings based on network feedback.
    private func adjustSettings(feedback: [String: Double]) {
        if let bandwidth = feedback["bandwidth"] {
            maxBitrate = UInt32(min(max(64_000, bandwidth / 2), 320_000)) // Example adjustment
            //TODO actual adjustment
        }

        if let latency = feedback["latency"] {
            frameSize = latency > 100 ? 576 : 1152 // Reduce frame size for high latency
        }
    }

    // Sets the Audio Converter to use Variable Bitrate mode.
    private func setVBRMode() {
        guard let audioConverter = audioConverter else { return }
        var controlMode: UInt32 = kAudioCodecBitRateControlMode_Variable
        AudioConverterSetProperty(
            audioConverter,
            kAudioCodecPropertyBitRateControlMode,
            UInt32(MemoryLayout.size(ofValue: controlMode)),
            &controlMode
        )

        var bitrate: UInt32 = maxBitrate
        AudioConverterSetProperty(
            audioConverter,
            kAudioConverterEncodeBitRate,
            UInt32(MemoryLayout.size(ofValue: bitrate)),
            &bitrate
        )
    }

    
    
    struct InputDataContext {
        var inputBufferList: AudioBufferList
        var inputDataPacketCount: UInt32
    }

//    static func inputDataProvider(
//        inAudioConverter: AudioConverterRef,
//        ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
//        ioData: UnsafeMutablePointer<AudioBufferList>,
//        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
//        inUserData: UnsafeMutableRawPointer?
//    ) -> OSStatus {
//        guard let userData = inUserData else {
//            return kAudio_ParamError
//        }
//        
//        // Extract the input buffer list and packet count from userData
//        let context = userData.assumingMemoryBound(to: InputDataContext.self).pointee
//        ioData.pointee = context.inputBufferList
//        ioNumberDataPackets.pointee = context.inputDataPacketCount
//        return noErr
//    }

    // Encodes PCM data to MP3.
    private func encodePCMToMP3(pcmData: PCMSpeech16) -> Data? {
        var outputData = Data()
        
        // Prepare input buffer list
        let pcmBuffer = pcmData.samples.withUnsafeBufferPointer { buffer in
            UnsafeMutableRawPointer(mutating: buffer.baseAddress)
        }
        var inputBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(pcmData.samples.count * MemoryLayout<Int16>.size),
                mData: pcmBuffer
            )
        )
        
        var inputDataPacketCount: UInt32 = UInt32(pcmData.samples.count / Int(pcmData.channelNum))
        let context = InputDataContext(inputBufferList: inputBufferList, inputDataPacketCount: inputDataPacketCount)
        
        // Allocate memory for the context
        let contextPointer = UnsafeMutablePointer<InputDataContext>.allocate(capacity: 1)
        contextPointer.initialize(to: context)
        defer {
            contextPointer.deinitialize(count: 1)
            contextPointer.deallocate()
        }

        // Prepare output buffer
        var outputDataPacketCount: UInt32 = 1
        let outputBufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer {
            outputBufferList.deallocate()
        }

        // Fill buffer using the audio converter
        let status = AudioConverterFillComplexBuffer(
            audioConverter!,
            inputDataProvider, // Use the static function
            contextPointer,             // Pass the context
            &outputDataPacketCount,
            outputBufferList,
            nil
        )
        
        if status != noErr {
            print("Error during encoding: \(status)")
            return nil
        }
        
        // Convert outputBufferList to Data
        for i in 0..<outputBufferList.pointee.mNumberBuffers {
            let buffer = outputBufferList.pointee.mBuffers
            outputData.append(UnsafeBufferPointer(start: buffer.mData?.assumingMemoryBound(to: UInt8.self), count: Int(buffer.mDataByteSize)))
        }
        
        return outputData
    }


    // Creates an `AudioStreamBasicDescription` for PCM input.
    private func createPCMFormat(sampleRate: Int, channels: Int) -> AudioStreamBasicDescription {
        return AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * MemoryLayout<Int16>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * MemoryLayout<Int16>.size),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
    }

    // Creates an `AudioStreamBasicDescription` for MP3 output.
    private func createMP3Format(sampleRate: Int, channels: Int) -> AudioStreamBasicDescription {
        return AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatMPEGLayer3,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(frameSize),
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
    }

    deinit {
        if let audioConverter = audioConverter {
            AudioConverterDispose(audioConverter)
        }
    }
}


func playbackMP3(data : Data){
    
}
