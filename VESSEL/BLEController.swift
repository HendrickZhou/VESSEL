//
//  BLEController.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/18/24.
//

import Foundation
import CoreBluetooth

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
    
    weak var delegate: AudioReceiverDelegate?
    
    // Replace with your actual PSM value provided by the hardware
    let l2capPSM: CBL2CAPPSM = 0x0041

    override init() {
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
        
        // Check MTU size
//        self.negotiatedMTU = channel.inputStream?.property(forKey: .dataWrittenToMemoryStreamKey) as? Int ?? 512
//        print("Negotiated MTU size: \(self.negotiatedMTU) bytes")
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
            guard let inputStream = aStream as? InputStream else {
                print("Stream is not an InputStream.")
                return
            }
            // Dynamically read all available data
            var receivedData = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024) // Temporary buffer
            defer { buffer.deallocate() }
            
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(buffer, maxLength: 1024) // Read up to 1024 bytes at a time
                if bytesRead > 0 {
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
                
                let rawData = receivedData.map { $0 }
                print("Raw Data (UInt8): \(rawData)")
                delegate?.didReceiveL2CAPData(data: rawData.map { String($0) }.joined(separator: " "))
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
//            aStream.close()
//            aStream.remove(from: .current, forMode: .default)
        
        default:
            print("Unhandled stream event: \(eventCode)")
        }
    }
}

// Stream delegate for handling incoming L2CAP data
//extension AudioReceiverCentral: StreamDelegate {
//    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
//        guard let inputStream = aStream as? InputStream else { return }
//
//        switch eventCode {
//        case .hasBytesAvailable:
//            var buffer = [UInt8](repeating: 0, count: negotiatedMTU) // Use MTU for buffer size
//            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
//            
//            if bytesRead > 0 {
//                // Append data and process the packet
//                let data = Data(buffer.prefix(bytesRead))
//                processIncomingData(data)
//            }
//            
//        case .endEncountered:
//            print("Stream ended.")
//            inputStream.close()
//            inputStream.remove(from: .current, forMode: .default)
//            
//        case .errorOccurred:
//            print("Stream error occurred.")
//            
//        default:
//            break
//        }
//    }
//
//    private func processIncomingData(_ data: Data) {
//        /*
//         extract message from streaming
//         */
//        receivedDataBuffer.append(data)
//        
//        while receivedDataBuffer.count >= 4 { // Minimum size for a complete message
//            // Peek into the buffer to determine the payload length
//            let length = UInt16(receivedDataBuffer[1]) << 8 | UInt16(receivedDataBuffer[2])
//            let totalMessageSize = Int(length) + 4
//            
//            // Wait until a complete message is available
//            if receivedDataBuffer.count < totalMessageSize { break }
//            
//            // Extract and process the complete message
//            let messageData = receivedDataBuffer.prefix(totalMessageSize)
//            receivedDataBuffer.removeFirst(totalMessageSize)
//            
//            if let message = L2CAPMessage(data: messageData) {
//                handleL2CAPMessage(message)
//            } else {
//                print("Invalid L2CAP message received.")
//            }
//        }
//    }
//    
//    private func handleL2CAPMessage(_ message: L2CAPMessage) {
//        /*
//         deal with different types of message
//         */
//        switch message.type {
//        case .control:
//            print("Received control message: \(message.payload)")
//            // Process control-specific logic
//        case .data:
//            print("Received data message: \(message.payload.count) bytes")
//            // Handle data payload (e.g., reassemble audio frames)
//            var qoaHandler = QOAFrameHandler()
//            if let frameData = qoaHandler.addPacket(message.payload) {
//                // add packet until a complete frame is done
//                handleCompleteFrame(frameData)
//            }
//        case .error:
//            print("Received error message: \(message.payload)")
//            // Handle error-specific logic
//        case .ack:
//            print("Received acknowledgment message.")
//            // Handle acknowledgment
//        case .info:
//            print("Received info message: \(message.payload)")
//            // Handle info-specific logic
//            handleAudioMetaInfo(message.payload)
//        }
//    }
//
//    private func handleCompleteFrame(_ frameData: Data) {
//        /*
//         deal with complete frame
//         */
//        // TODO
//        // Placeholder for processing the reassembled QOA frame
//        // Consider parsing headers for control/error detection if included
//        print("Received complete frame of size: \(frameData.count) bytes")
//        // Insert code for decoding or playback of QOA audio here
//    }
//    
//    private func handleAudioMetaInfo(_ metaData: Data) {
//        // deal with audio metat data, like sampling rate, channels etc
//    }
//}
