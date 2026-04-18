//
//  InstrumentControlView.swift
//  PhysicAI
//
//  Extracted from ContentView.swift for floating window support.
//

import SwiftUI

struct InstrumentControlView: View {
    @EnvironmentObject var instrumentManager: InstrumentManager
    @State private var selectedInstrumentID: UUID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Instrument Control")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button("View Logs") {
                        openWindow(id: "diagnostics-console")
                    }
                    .instrumentGlassButtonStyle()
                }

                // MARK: Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    Text(instrumentManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let connected = instrumentManager.connectedDevice {
                        Text("Connected: \(connected.model) • \(connected.address)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(instrumentPanelBackground)
                .cornerRadius(16)

                // MARK: Device Discovery
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Device Discovery")
                            .font(.headline)
                        Spacer()
                        if instrumentManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    if instrumentManager.devices.isEmpty {
                        Text("No devices discovered yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.devices) { device in
                            let isSelected = device.id == selectedInstrumentID
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.model)
                                        .font(.caption)
                                    Text(device.address)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    instrumentTagChip("Selected")
                                }
                            }
                            .padding(8)
                            .background(isSelected ? Color.blue.opacity(0.12) : Color.gray.opacity(0.08))
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedInstrumentID = device.id
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Scan") {
                            instrumentManager.scan()
                        }
                        Button("Add Manual Endpoint") {
                            // Not implemented yet
                        }
                    }
                    .instrumentGlassButtonStyle()
                }
                .padding(12)
                .background(instrumentPanelBackground)
                .cornerRadius(16)

                // MARK: Connection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("Connect") {
                            if let device = selectedInstrument {
                                instrumentManager.connect(to: device)
                            }
                        }
                        .disabled(selectedInstrument == nil || instrumentManager.isConnected)
                        Button("Disconnect") {
                            instrumentManager.disconnect()
                        }
                        .disabled(!instrumentManager.isConnected)
                    }
                    .instrumentGlassButtonStyle()
                }
                .padding(12)
                .background(instrumentPanelBackground)
                .cornerRadius(16)

                // MARK: Command Queue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Queue")
                        .font(.headline)
                    if instrumentManager.commandQueue.isEmpty {
                        Text("Queue is empty.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.commandQueue) { command in
                            Text(command.name)
                                .font(.caption)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Get Status") {
                            instrumentManager.send(InstrumentCommand(name: "Get Status"))
                        }
                        Button("Start Scan") {
                            instrumentManager.send(InstrumentCommand(name: "Start Scan"))
                        }
                        Button("Stop") {
                            instrumentManager.send(InstrumentCommand(name: "Stop"))
                        }
                    }
                    .disabled(!instrumentManager.isConnected)
                    .instrumentGlassButtonStyle()
                }
                .padding(12)
                .background(instrumentPanelBackground)
                .cornerRadius(16)

                // MARK: Recent Responses
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Responses")
                        .font(.headline)
                    if instrumentManager.responses.isEmpty {
                        Text("No responses yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(instrumentManager.responses.suffix(6), id: \.timestamp) { response in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedTimestamp(response.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(response.message)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(12)
                .background(instrumentPanelBackground)
                .cornerRadius(16)
            }
            .padding(24)
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 500)
    }

    // MARK: - Helpers

    private var selectedInstrument: InstrumentDevice? {
        guard let selectedInstrumentID else { return nil }
        return instrumentManager.devices.first { $0.id == selectedInstrumentID }
    }

    private var instrumentPanelBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.platformBackground.opacity(0.6))
    }

    private func instrumentTagChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.platformBackground.opacity(0.85))
            .cornerRadius(10)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Glass Button Style (local copy for standalone window)

private extension View {
    @ViewBuilder
    func instrumentGlassButtonStyle(isProminent: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
            if isProminent {
                self.buttonStyle(.borderedProminent)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
