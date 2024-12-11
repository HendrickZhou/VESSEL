//
//  ContentView.swift
//  VESSEL
//
//  Created by Zhou Hang on 11/18/24.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    
    var body: some View {
        VStack {
            if bleManager.isConnected {
                if bleManager.isL2CAPConnected {
                    // Show L2CAP Stream Data
                    Text("Streaming L2CAP Data:")
                        .font(.headline)
                    ScrollView {
                        Text(bleManager.l2capData)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Show button to establish L2CAP connection
                    Button("Open L2CAP Channel") {
                        bleManager.openL2CAPChannel()
                    }
                    .padding()
                }
            } else {
                if bleManager.isScanning {
                    Text("Scanning for STM devices...")
                    List(bleManager.discoveredDevices, id: \.identifier) { peripheral in
                        Button(action: {
                            bleManager.connectToDevice(peripheral)
                        }) {
                            Text(peripheral.name ?? "Unnamed Device")
                        }
                    }
                } else {
                    Text("Bluetooth is not ready or scanning stopped.")
                        .padding()
                }
            }
        }
        .padding()
        .onAppear {
            bleManager.startBLEDiscovery()
        }
//        .onDisappear {
//            bleManager.stopBLEDiscovery()
//        }
    }
}

#Preview {
    ContentView()
}
