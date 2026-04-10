import Foundation
import Combine

struct InstrumentDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let model: String
    let address: String

    init(name: String, model: String, address: String) {
        self.id = UUID()
        self.name = name
        self.model = model
        self.address = address
    }
}

struct InstrumentCommand: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let payload: String

    init(name: String, payload: String = "") {
        self.id = UUID()
        self.name = name
        self.payload = payload
    }
}

struct InstrumentResponse: Hashable, Sendable {
    let timestamp: Date
    let message: String
}

protocol InstrumentDriver: Sendable {
    func discoverDevices() async -> [InstrumentDevice]
    func connect(to device: InstrumentDevice) async throws
    func disconnect() async
    func send(_ command: InstrumentCommand) async throws -> InstrumentResponse
    var isConnected: Bool { get }
    var connectedDevice: InstrumentDevice? { get }
}

final class MockInstrumentDriver: InstrumentDriver {
    private var connected: InstrumentDevice?

    var isConnected: Bool { connected != nil }
    var connectedDevice: InstrumentDevice? { connected }

    func discoverDevices() async -> [InstrumentDevice] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        return [
            InstrumentDevice(name: "UV-Vis", model: "SolidSpec-3700i", address: "usb://shimadzu/uv/3700i"),
            InstrumentDevice(name: "UV-Vis (Lab)", model: "UV-2600i", address: "tcp://192.168.1.120:5000")
        ]
    }

    func connect(to device: InstrumentDevice) async throws {
        try? await Task.sleep(nanoseconds: 250_000_000)
        connected = device
    }

    func disconnect() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
        connected = nil
    }

    func send(_ command: InstrumentCommand) async throws -> InstrumentResponse {
        try? await Task.sleep(nanoseconds: 200_000_000)
        let message = "Mock response for \(command.name) \(command.payload.isEmpty ? "" : "(\(command.payload))")"
        return InstrumentResponse(timestamp: Date(), message: message)
    }
}

@MainActor
final class InstrumentManager: ObservableObject {
    @Published private(set) var devices: [InstrumentDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedDevice: InstrumentDevice?
    @Published private(set) var statusMessage = "Not connected"
    @Published private(set) var commandQueue: [InstrumentCommand] = []
    @Published private(set) var responses: [InstrumentResponse] = []

    private let driver: InstrumentDriver

    init(driver: InstrumentDriver) {
        self.driver = driver
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        statusMessage = "Scanning for instruments…"
        Task {
            let found = await driver.discoverDevices()
            devices = found
            isScanning = false
            statusMessage = found.isEmpty ? "No devices found" : "Found \(found.count) device(s)"
        }
    }

    func connect(to device: InstrumentDevice) {
        statusMessage = "Connecting to \(device.model)…"
        Task {
            do {
                try await driver.connect(to: device)
                connectedDevice = device
                isConnected = true
                statusMessage = "Connected to \(device.model)"
            } catch {
                statusMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        statusMessage = "Disconnecting…"
        Task {
            await driver.disconnect()
            connectedDevice = nil
            isConnected = false
            statusMessage = "Not connected"
        }
    }

    func send(_ command: InstrumentCommand) {
        guard isConnected else {
            statusMessage = "Connect to a device first"
            return
        }
        commandQueue.append(command)
        Task {
            do {
                let response = try await driver.send(command)
                responses.append(response)
                statusMessage = response.message
            } catch {
                statusMessage = "Command failed: \(error.localizedDescription)"
            }
            if let index = commandQueue.firstIndex(of: command) {
                commandQueue.remove(at: index)
            }
        }
    }
}
