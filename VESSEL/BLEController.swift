//
//  BLEController.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/18/24.
//

import Foundation
import CoreBluetooth
import AVFoundation

protocol AudioReceiverDelegate: AnyObject {
    func didReadyForAdv()
    func didUpdateConnectionState(isConnected: Bool)
    func didReceiveL2CAPData(data: String)
    func didEstablishL2CAPConnection()
    func didDiscoverPeripheral(_ peripheral: CBPeripheral)
}

class BLEManager: NSObject, ObservableObject {
    @Published var readyForScan = false
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var isL2CAPConnected = false
    @Published var l2capData = ""
    @Published var discoveredDevices: [CBPeripheral] = []
    
//    private var audioPlaybackManager: AudioPlaybackManager? = AudioPlaybackManager()
    private var audioReceiver: AudioReceiverCentral?

    override init() {
        super.init()
        self.audioReceiver = AudioReceiverCentral()
        self.audioReceiver?.delegate = self
    }

    func startBLEDiscovery() {
//        while(!readyForScan) {print("***")}
        if readyForScan {
            self.audioReceiver?.startScanning()
            self.isScanning = true
        } else {
            print("wait for bluetooth to get ready")
        }
        
    }
    
//    func stopBLEDiscovery() {
//        self.audioReceiver?.stopScanning()
//        self.isScanning = false
//    }
    
    func connectToDevice(_ peripheral: CBPeripheral) {
        self.audioReceiver?.connectToPeripheral(peripheral)
    }

    func openL2CAPChannel() {
        if isConnected {
            self.audioReceiver?.openL2CAPChannel()
        } else {
            print("BLE connection is not up, can't set up L2cap link")
        }
    }
}



class AudioReceiverCentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var connectedPeripheral: CBPeripheral?
    var l2capChannel: CBL2CAPChannel?
    var receivedDataBuffer = Data()
    var negotiatedMTU: Int = 512

    var incompleteFrameBuffer = Data()
    var expectedFrameLength: Int?
    private var pcmPlayer: PCMPlayer

    
    weak var delegate: AudioReceiverDelegate?
        
    // Replace with your actual PSM value provided by the hardware
    let l2capPSM: CBL2CAPPSM = 0x0041

    override init() {
        pcmPlayer = PCMPlayer()
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
    
    
    // manually start scanning when ready
    func startScanning() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            print("Scanning for peripherals...")
        } else {
            print("Bluetooth is not ready. Current state: \(centralManager.state.rawValue)")
        }
    }

//    // Start scanning once Bluetooth is ready
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state{
        case .poweredOn:
            delegate?.didReadyForAdv()
        case .poweredOff:
            print("Bluetooth is Off")
        case .resetting:
            print("Bluetooth is Resetting")
        case .unauthorized:
            print("Bluetooth is Unauthorized")
        case .unsupported:
            print("Bluetooth is Unsupported")
        case .unknown:
            print("Bluetooth status is Unknown")
        @unknown default:
            print("Unknown state")
        }
    }

    // Discover and connect to the hardware
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        if let name = peripheral.name, name.contains("STM") {
            print("Discovered STM device: \(name)")
            delegate?.didDiscoverPeripheral(peripheral)
            connectedPeripheral = peripheral
            connectedPeripheral?.delegate = self
            centralManager.stopScan()
        }
        // hand over control to user
    }
    
    func connectToPeripheral(_ peripheral: CBPeripheral){
        centralManager.connect(peripheral, options: nil)
    }
    
//    func stopScanning() {
//        centralManager.stopScan()
//    }

    // Connection established, open L2CAP channel
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        delegate?.didUpdateConnectionState(isConnected: true)
    }
    
    func openL2CAPChannel() {
        guard let peripheral = connectedPeripheral else {
            print("No connected peripheral to open L2CAP channel.")
            return
        }
        peripheral.openL2CAPChannel(l2capPSM)
        print("Attempting to open L2CAP channel on PSM \(l2capPSM).")
    }
    
    // L2CAP channel opened, handle incoming data
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        if let error = error {
            print("Error opening L2CAP channel: \(error.localizedDescription)")
            return
        }
        
        guard let channel = channel else {
            print("No channel returned.")
            return
        }
        
        self.l2capChannel = channel
        delegate?.didEstablishL2CAPConnection()
        
        channel.inputStream?.delegate = self
        channel.inputStream?.schedule(in: .current, forMode: .default)
        channel.inputStream?.open()
        
        print("L2CAP channel opened successfully. Awaiting data packets.")
    }

    // Disconnect and clean up
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        l2capChannel = nil
        delegate?.didUpdateConnectionState(isConnected: false)
    }
}

extension AudioReceiverCentral: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print("Stream status: \(aStream.streamStatus.rawValue)")
        switch eventCode {
        case .openCompleted:
            print("Stream opened successfully.")
        
        case .hasBytesAvailable:
            print("status: hasBytesAvailable")
            guard let inputStream = aStream as? InputStream else {
                print("Stream is not an InputStream.")
                return
            }
            // Dynamically read all available data
            var receivedData = Data()
            var buffer = [UInt8](repeating: 0, count: 1024) // Temperary buffer
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: buffer.count) // Read up to 1024 bytes at a time
                if bytesRead > 0 {
                    processReceivedData(Data(buffer[0..<bytesRead]))
                    receivedData.append(buffer, count: bytesRead)
                } else if bytesRead == 0 {
                    print("No more data available in stream.")
                    break
                } else {
                    print("Error reading from input stream.")
                    break
                }
            }
            
            if !receivedData.isEmpty {
                print("Received Data: \(receivedData.count) bytes")
                
//                let rawData = receivedData.map { $0 }
//                print("Raw Data (UInt8): \(rawData)")
//                delegate?.didReceiveL2CAPData(data: rawData.map { String($0) }.joined(separator: " "))
//                delegate?.didReceiveL2CAPData(data: String)
            }
        
        case .hasSpaceAvailable:
            print("Stream has space available for writing.")
        
        case .errorOccurred:
            if let streamError = aStream.streamError {
                print("Stream error occurred: \(streamError.localizedDescription)")
            } else {
                print("Unknown stream error occurred.")
            }
        
        case .endEncountered:
            print("Stream has reached its end.")
            aStream.close()
            aStream.remove(from: .current, forMode: .default)
        
        default:
            print("Unhandled stream event: \(eventCode)")
        }
    }

    private func processReceivedData(_ data: Data) {
        // Append new data to the buffer
        incompleteFrameBuffer.append(data)

        while true {
            // Step 1: Check if we are waiting for the header
            if expectedFrameLength == nil {
                // Ensure at least 3 bytes are available for the header
                guard incompleteFrameBuffer.count >= 3 else {
                    print("Not enough data for the header. Waiting for more data.")
                    break
                }

                // Extract the control bit and frame length from the first 3 bytes
                let controlBit = incompleteFrameBuffer[0]
                let lengthLSB = UInt16(incompleteFrameBuffer[1]) // Least significant byte
                let lengthMSB = UInt16(incompleteFrameBuffer[2]) // Most significant byte
                expectedFrameLength = Int((lengthMSB << 8) | lengthLSB) // Combine bytes

                print("Control Bit: \(controlBit)")
                print("Detected frame length: \(expectedFrameLength!)")

                // Remove the processed header (3 bytes) from the buffer
                incompleteFrameBuffer.removeSubrange(0..<3)
            }

            // Step 2: Check if the full frame is available
            if let frameLength = expectedFrameLength, incompleteFrameBuffer.count >= frameLength {
                // Extract the frame data
                let frameData = incompleteFrameBuffer[0..<frameLength]
                incompleteFrameBuffer.removeSubrange(0..<frameLength)

                // Reset expectedFrameLength for the next frame
                expectedFrameLength = nil

                // Process the complete frame
                handleCompleteFrame(frameData)
            } else {
                // Not enough data for the full frame, wait for more
                break
            }
        }
    }


    private func handleCompleteFrame(_ frameData: Data) {
        print("Complete frame received: \(frameData.count) bytes")
        pcmPlayer.playPCMData(frameData)
    }

}
