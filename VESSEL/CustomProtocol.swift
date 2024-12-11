//
//  L2CAPMessage.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/19/24.
//

import Foundation

/*
Custom L2CAP Message Specification

This specification defines a simple and flexible structure for transmitting control and data messages over an L2CAP channel.

---

### Message Structure
Each message comprises a **header** and an optional **payload**:

| Field             | Size           | Description                                      |
|--------------------|----------------|--------------------------------------------------|
| Message Type       | 1 byte         | Identifies the type of message (e.g., control or data). |
| Message Length     | 2 bytes (UInt16) | Length of the payload in bytes (big-endian format). |
| Payload            | Variable       | Data specific to the message type.              |
| Checksum           | 1 byte         | XOR checksum of the entire message (excluding the checksum field). |

---

### Message Types

| Type (Hex) | Description                           | Payload Example                               |
|------------|---------------------------------------|-----------------------------------------------|
| 0x01       | Control Message                      | MTU size, connection flags, or other metadata.|
| 0x02       | Data Message                         | Audio frame data (partial or complete).       |
| 0x03       | Error Message                        | Error codes or diagnostics.                  |
| 0x04       | Acknowledgment                      | Acknowledges receipt of a specific message.  |

---

### Header Field Details

1. **Message Type (1 byte)**:
   Identifies the purpose of the message (e.g., control, data, error).

2. **Message Length (2 bytes)**:
   Specifies the payload size in bytes, encoded in **big-endian format**.

3. **Payload (Variable)**:
   Contains the data associated with the message type. The content depends on the type.

4. **Checksum (1 byte)**:
   XOR checksum for verifying message integrity.

---

### Example Messages

#### 1. Control Message for MTU Size
| Field           | Value          | Description                          |
|------------------|----------------|--------------------------------------|
| Message Type     | 0x01           | Control message.                     |
| Message Length   | 0x0002         | 2 bytes for MTU size.                |
| Payload          | 0x0200 (512)   | MTU size is 512 bytes.               |
| Checksum         | 0x03           | XOR of 0x01, 0x00, 0x02, 0x02, 0x00. |

Serialized: `0x01 0x00 0x02 0x02 0x00 0x03`

#### 2. Data Message for Audio Frame
| Field           | Value          | Description                          |
|------------------|----------------|--------------------------------------|
| Message Type     | 0x02           | Data message.                        |
| Message Length   | 0x0800 (2048)  | 2048 bytes of audio data.            |
| Payload          | Audio frame    | Raw audio data.                      |
| Checksum         | 0x02           | Example checksum value.              |

Serialized: `0x02 0x08 0x00 [Audio Data (2048 bytes)] 0x02`

---

### Error Detection and Handling

1. **Header Validation**:
   - Verify that `Message Length` matches the actual payload size.
   - Reject or log messages with invalid or mismatched lengths.

2. **Unknown Message Types**:
   - Ignore or log messages with unrecognized `Message Type` values.

3. **Checksum Validation**:
   - Ensure data integrity by verifying the checksum or adding an additional checksum/CRC field in the payload.

---
*/


struct L2CAPMessage {
    enum MessageType: UInt8 {
        case data = 0x01
        case control = 0x02
        case error = 0x03
        case ack = 0x04
        case info = 0x05
    }
    
    let type: MessageType
    var length: UInt16 {
        return UInt16(payload.count)
    }
    let payload: Data
    
    init(type: MessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }
    
    // Initializes an L2CAP message from raw data
    init?(data: Data) {
        guard data.count > 4 else { return nil } // Minimum header size: 1 byte (type) + 2 bytes (length) + 1 byte (checksum)
        
        // Parse header
        guard let messageType = MessageType(rawValue: data[0]) else { return nil }
        self.type = messageType
        
        let payloadLength = UInt16(data[1]) << 8 | UInt16(data[2])
        
        // Verify payload size matches length
        guard data.count == Int(payloadLength) + 4 else { return nil }
        
        self.payload = data[3..<3 + Int(payloadLength)]
        
        // Validate checksum
        let checksum = data.last!
        let calculatedChecksum = L2CAPMessage.calculateChecksum(data.dropLast())
        guard checksum == calculatedChecksum else { return nil }
    }
    
    func toData() -> Data {
        var data = Data()
        data.append(type.rawValue)
        data.append(UInt8(length >> 8)) // Big-endian
        data.append(UInt8(length & 0xFF))
        data.append(payload)
        let checksum = L2CAPMessage.calculateChecksum(data)
        data.append(checksum)
        return data
    }
    
    static func calculateChecksum(_ data: Data) -> UInt8 {
        return data.reduce(0, ^) // XOR
    }
}

/*
QOA Packet Protocol

This protocol defines the structure and handling of packets used to transmit QOA-encoded audio frames over BLE.

---

### **Packet Structure**
Each QOA packet consists of a **header** followed by a **payload**:

| **Field**          | **Size**             | **Description**                                           |
|---------------------|----------------------|-----------------------------------------------------------|
| **Frame ID**        | 2 bytes (UInt16)     | Identifies the QOA frame this packet belongs to.          |
| **Segment ID**      | 1 byte (UInt8)       | Index of this packet within the frame.                   |
| **Total Segments**  | 1 byte (UInt8)       | Total number of packets for the frame.                   |
| **Payload**         | Variable             | Segment of the QOA frame data.                           |

---

### **Field Details**

1. **Frame ID (2 bytes)**:
   - Unique identifier for the QOA frame this packet belongs to.
   - Wraps around after reaching `65535`.

2. **Segment ID (1 byte)**:
   - Sequential index for the packet within the frame.
   - Starts at `0` and increments up to `Total Segments - 1`.

3. **Total Segments (1 byte)**:
   - Indicates the total number of packets for the QOA frame.
   - Ensures the receiver can detect missing or incomplete frames.

4. **Payload (Variable)**:
   - A portion of the QOA frame data.
   - Size is determined by the negotiated BLE MTU minus the header size (`4 bytes`).

---

### **Packet Example**

#### 1. **First Packet of a QOA Frame**
| **Field**            | **Value**          | **Description**                        |
|-----------------------|--------------------|----------------------------------------|
| **Frame ID**          | `0x0001`          | QOA frame identifier.                  |
| **Segment ID**        | `0x00`            | First segment in the frame.            |
| **Total Segments**    | `0x04`            | Frame requires 4 packets.              |
| **Payload**           | `[...]`           | First chunk of the QOA frame data.     |

**Serialized as**: `0x00 0x01 0x00 0x04 [...]`

#### 2. **Last Packet of the Same Frame**
| **Field**            | **Value**          | **Description**                        |
|-----------------------|--------------------|----------------------------------------|
| **Frame ID**          | `0x0001`          | QOA frame identifier.                  |
| **Segment ID**        | `0x03`            | Fourth segment (last one).             |
| **Total Segments**    | `0x04`            | Total segments remain consistent.      |
| **Payload**           | `[...]`           | Last chunk of the QOA frame data.      |

**Serialized as**: `0x00 0x01 0x03 0x04 [...]`

---

### **Reassembly Process**

1. **Identify Frame**:
   - Group packets by `Frame ID`.

2. **Order Segments**:
   - Use `Segment ID` to arrange packets sequentially.

3. **Verify Completion**:
   - Ensure all `Total Segments` packets are received before processing the frame.

4. **Reassemble**:
   - Concatenate payloads from all segments to reconstruct the QOA frame.

---

### **Error Handling**

1. **Missing Packets**:
   - If packets for a `Frame ID` are incomplete, discard the frame.

2. **Out-of-Order Packets**:
   - Handle segments using `Segment ID` to ensure correct ordering.

3. **Corrupted Packets**:
   - Rely on L2CAPMessage chec
*/

struct QOAFrameHandler {
    struct QOAPacket {
        let frameID: UInt16
        let segmentID: UInt8
        let totalSegments: UInt8
        let data: Data
        
        init?(data:Data) {
            guard data.count > 4 else { return nil } // Ensure minimum header size
            self.frameID = UInt16(data[0]) << 8 | UInt16(data[1])
            self.segmentID = data[2]
            self.totalSegments = data[3]
            self.data = data[4...] // Extract the payload
        }
    }
    
    private var frames: [UInt16: [UInt8: Data]] = [:]
    private var frameSizes: [UInt16: Int] = [:]
    
    mutating func addPacket(_ packetData: Data) -> Data? {
        // Parse the packet
        guard let packet = QOAPacket(data: packetData) else {
            print("Invalid QOA packet received.")
            return nil
        }
        
        // Initialize the frame if not already present
        if frames[packet.frameID] == nil {
            frames[packet.frameID] = [:]
            frameSizes[packet.frameID] = Int(packet.totalSegments)
        }
        
        // Store the packet
        frames[packet.frameID]?[packet.segmentID] = packet.data
        
        // Check if all segments are present
        if frames[packet.frameID]?.count == frameSizes[packet.frameID] {
            // Reassemble the frame
            let frameData = reassembleFrame(frameID: packet.frameID)
            
            // Clean up after reassembly
            frames.removeValue(forKey: packet.frameID)
            frameSizes.removeValue(forKey: packet.frameID)
            
            return frameData
        }
        
        return nil
    }
    
    private func reassembleFrame(frameID: UInt16) -> Data {
        guard let segments = frames[frameID] else { return Data() }
        
        // Combine segments in order
        var frameData = Data()
        for segmentID in 0..<UInt8(frameSizes[frameID] ?? 0) {
            if let segment = segments[segmentID] {
                frameData.append(segment)
            }
        }
        
        return frameData
    }
}
