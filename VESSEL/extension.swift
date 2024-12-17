//
//  extension.swift
//  VESSEL
//
//  Created by Zhou Hang on 12/10/24.
//

import Foundation
import CoreBluetooth

extension BLEManager: AudioReceiverDelegate {
    func didReadyForAdv() {
        DispatchQueue.main.async {
            self.readyForScan = true
            print("Bluetooth is ready. You can start scanning.")
            self.startBLEDiscovery() // Automatically start discovery when ready
        }
    }
    func didUpdateConnectionState(isConnected: Bool) {
        DispatchQueue.main.async {
            self.isConnected = isConnected
            if !isConnected {
                self.isScanning = true
                self.isL2CAPConnected = false
                self.l2capData = ""
                self.discoveredDevices.removeAll()
                self.startBLEDiscovery()  // automatically restart discovery
            }
        }
    }

    func didReceiveL2CAPData(data: String) {
        DispatchQueue.main.async {
            self.l2capData += data
//            audioPlaybackManager?.play(data: data)
        }
    }

    func didEstablishL2CAPConnection() {
        DispatchQueue.main.async {
            self.isL2CAPConnected = true
        }
    }
    
    func didDiscoverPeripheral(_ peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredDevices.append(peripheral)
            }
        }
    }
}
