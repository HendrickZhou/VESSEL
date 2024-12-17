//
//  playback.swift
//  VESSEL
//
//  Created by Zhou Hang on 12/16/24.
//

import Foundation
import AVFoundation

class PCMPlayer {
    private var audioEngine: AVAudioEngine
    private var audioPlayerNode: AVAudioPlayerNode
    private var audioFormat: AVAudioFormat

    init() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()

        // Define the audio format for 8kHz, 1 channel, Float32
        let sampleRate: Double = 8000.0
        let channelCount: UInt32 = 1
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        // Attach and connect the player node
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)

        // Start the audio engine
        do {
            try audioEngine.start()
            print("Audio engine started successfully.")
        } catch {
            fatalError("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    func playPCMData(_ pcmData: Data) {
        guard let floatBuffer = convertPCMDataToFloat32Buffer(pcmData) else {
            print("Failed to create Float32 audio buffer.")
            return
        }

        audioPlayerNode.scheduleBuffer(floatBuffer, completionHandler: nil)

        if !audioPlayerNode.isPlaying {
            audioPlayerNode.play()
        }
    }

    private func convertPCMDataToFloat32Buffer(_ pcmData: Data) -> AVAudioPCMBuffer? {
        // Calculate the number of frames
        let int16Samples = pcmData.count / MemoryLayout<Int16>.size
        guard int16Samples > 0 else {
            print("No valid samples in PCM data.")
            return nil
        }

        // Allocate Float32 buffer
        guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(int16Samples)
        ) else {
            return nil
        }
        audioBuffer.frameLength = AVAudioFrameCount(int16Samples)

        // Convert Int16 samples to Float32
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let int16Pointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            let float32Pointer = audioBuffer.floatChannelData![0]

            for i in 0..<int16Samples {
                float32Pointer[i] = Float(int16Pointer[i]) / 32768.0
            }
        }

        return audioBuffer
    }
}
