//
//  BLEController.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/18/24.
//

import Foundation
import CoreBluetooth

class AudioReceiverCentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var connectedPeripheral: CBPeripheral?
    var l2capChannel: CBL2CAPChannel?
    var receivedDataBuffer = Data()
    var negotiatedMTU: Int = 512
    
    // Replace with your actual PSM value provided by the hardware
    let l2capPSM: CBL2CAPPSM = 0x0041

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // Start scanning once Bluetooth is ready
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            print("Scanning for peripherals...")
        } else {
            print("Bluetooth is not available.")
        }
    }

    // Discover and connect to the hardware
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        
        // Stop scanning and connect to the found peripheral
        centralManager.stopScan()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    // Connection established, open L2CAP channel
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        
        // Open the L2CAP channel on the specified PSM
        peripheral.openL2CAPChannel(l2capPSM)
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
        channel.inputStream?.delegate = self
        channel.inputStream?.schedule(in: .current, forMode: .default)
        channel.inputStream?.open()

        print("L2CAP channel opened successfully. Awaiting data packets.")
        
        // Check MTU size
        self.negotiatedMTU = channel.inputStream?.property(forKey: .dataWrittenToMemoryStreamKey) as? Int ?? 512
        print("Negotiated MTU size: \(self.negotiatedMTU) bytes")
        sendMTUToPeripheral()
    }
    

    func sendMTUToPeripheral() {
        guard let outputStream = l2capChannel?.outputStream else { return }

        let mtuPayload = Data([UInt8(negotiatedMTU >> 8), UInt8(negotiatedMTU & 0xFF)])
        let controlMessage = L2CAPMessage(type: .control, payload: mtuPayload)
        
        let messageData = controlMessage.toData()
        messageData.withUnsafeBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {return}
            outputStream.write(bytes, maxLength: messageData.count)
        }
        print("MTU size \(negotiatedMTU) bytes sent as control message via L2CAP")
    }

    // Disconnect and clean up
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        l2capChannel = nil
    }
}

// Stream delegate for handling incoming L2CAP data
extension AudioReceiverCentral: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }

        switch eventCode {
        case .hasBytesAvailable:
            var buffer = [UInt8](repeating: 0, count: negotiatedMTU) // Use MTU for buffer size
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            
            if bytesRead > 0 {
                // Append data and process the packet
                let data = Data(buffer.prefix(bytesRead))
                processIncomingData(data)
            }
            
        case .endEncountered:
            print("Stream ended.")
            inputStream.close()
            inputStream.remove(from: .current, forMode: .default)
            
        case .errorOccurred:
            print("Stream error occurred.")
            
        default:
            break
        }
    }

    private func processIncomingData(_ data: Data) {
        /*
         extract message from streaming
         */
        receivedDataBuffer.append(data)
        
        while receivedDataBuffer.count >= 4 { // Minimum size for a complete message
            // Peek into the buffer to determine the payload length
            let length = UInt16(receivedDataBuffer[1]) << 8 | UInt16(receivedDataBuffer[2])
            let totalMessageSize = Int(length) + 4
            
            // Wait until a complete message is available
            if receivedDataBuffer.count < totalMessageSize { break }
            
            // Extract and process the complete message
            let messageData = receivedDataBuffer.prefix(totalMessageSize)
            receivedDataBuffer.removeFirst(totalMessageSize)
            
            if let message = L2CAPMessage(data: messageData) {
                handleL2CAPMessage(message)
            } else {
                print("Invalid L2CAP message received.")
            }
        }
    }
    
    private func handleL2CAPMessage(_ message: L2CAPMessage) {
        /*
         deal with different types of message
         */
        switch message.type {
        case .control:
            print("Received control message: \(message.payload)")
            // Process control-specific logic
        case .data:
            print("Received data message: \(message.payload.count) bytes")
            // Handle data payload (e.g., reassemble audio frames)
            var qoaHandler = QOAFrameHandler()
            if let frameData = qoaHandler.addPacket(message.payload) {
                // add packet until a complete frame is done
                handleCompleteFrame(frameData)
            }
        case .error:
            print("Received error message: \(message.payload)")
            // Handle error-specific logic
        case .ack:
            print("Received acknowledgment message.")
            // Handle acknowledgment
        }
    }

    private func handleCompleteFrame(_ frameData: Data) {
        /*
         deal with complete frame
         */
        // TODO
        // Placeholder for processing the reassembled QOA frame
        // Consider parsing headers for control/error detection if included
        print("Received complete frame of size: \(frameData.count) bytes")
        // Insert code for decoding or playback of QOA audio here
    }
}
