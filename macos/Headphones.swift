import Foundation
import SwiftUI

struct ListeningMode: Codable, Identifiable {
    let id: Int
    let name: String
    let command: String

    var icon: String {
        switch command {
        case "quiet": "waveform.slash"
        case "aware": "ear"
        case "immersion": "waveform"
        case "cinema": "film"
        default: "slider.horizontal.3"
        }
    }
}

struct AudioSettings: Codable {
    var cncLevel: Int
    var spatial: Int
    var windBlock: Bool
    var ancToggle: Bool

    enum CodingKeys: String, CodingKey {
        case cncLevel = "cnc_level", spatial, windBlock = "wind_block", ancToggle = "anc_toggle"
    }
}

struct EQBand: Codable, Identifiable {
    let id: Int
    let name: String
    let minimum: Int
    let maximum: Int
    var value: Int
}

struct Headphones: Codable {
    let model: String
    var name: String?
    var firmware: String?
    var battery: Int?
    var profiles: [ListeningMode]?
    var mode: Int?
    var audio: AudioSettings?
    var anr: String?
    var eq: [EQBand]?
    var sidetone: String?
    var multipoint: Bool?
    var autoPause: Bool?
    var autoAnswer: Bool?
    var prompts: Bool?
    var unavailable: [String]

    var title: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? model }
    var activeMode: String? { profiles?.first { $0.id == mode }?.name ?? anr?.capitalized }

    static let demo = Headphones(
        model: "Bose QuietComfort Ultra (2nd Gen)", name: "QuietComfort Ultra",
        firmware: "8.2.20", battery: 78,
        profiles: [
            .init(id: 0, name: "Quiet", command: "quiet"),
            .init(id: 1, name: "Aware", command: "aware"),
            .init(id: 2, name: "Immersion", command: "immersion"),
            .init(id: 3, name: "Cinema", command: "cinema"),
        ], mode: 0, audio: .init(cncLevel: 2, spatial: 0, windBlock: false, ancToggle: true),
        eq: [
            .init(id: 0, name: "Bass", minimum: -10, maximum: 10, value: 3),
            .init(id: 1, name: "Mid", minimum: -10, maximum: 10, value: 0),
            .init(id: 2, name: "Treble", minimum: -10, maximum: 10, value: 2),
        ], sidetone: "low", multipoint: true, autoPause: true, autoAnswer: false,
        prompts: true, unavailable: []
    )
}

enum SettingValue: Encodable, Sendable {
    case number(Int), text(String), toggle(Bool), bands([Int])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .toggle(let value): try container.encode(value)
        case .bands(let values): try container.encode(values)
        }
    }
}

private struct BridgeRequest: Encodable, Sendable {
    var address: String?
    var deviceType: String?
    var control: String?
    var value: SettingValue?
    var previous: Headphones?
}

private struct BridgeReply: Decodable, Sendable {
    var snapshot: Headphones?
    var address: String?
    var deviceType: String?
    var warning: String?
    var error: String?
}

private struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func runBridge(_ request: BridgeRequest) throws -> BridgeReply {
    let bundle = Bundle.main
    guard let python = bundle.object(forInfoDictionaryKey: "BoseControlPython") as? String,
          FileManager.default.isExecutableFile(atPath: python),
          let script = bundle.url(forResource: "bridge", withExtension: "py") else {
        throw BridgeError(message: "The Python environment is missing. Rebuild Bose Control from the repository.")
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: python)
    process.arguments = ["-B", "-E", script.path, String(decoding: try JSONEncoder().encode(request), as: UTF8.self)]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()

    // A failed OS-level Bluetooth call can outlive the backend's own timeouts.
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
    defer { timeout.cancel() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let reason = process.terminationReason == .uncaughtSignal
            ? "The Bluetooth helper stopped. Check Bluetooth permission in System Settings and try again."
            : "The Bluetooth helper could not start. Rebuild Bose Control to check its Python dependencies."
        throw BridgeError(message: reason)
    }
    return try JSONDecoder().decode(BridgeReply.self, from: data)
}

@MainActor
final class HeadphoneStore: ObservableObject {
    @Published private(set) var headphones: Headphones?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    let demo: Bool

    private var address: String?
    private var deviceType: String?

    init(demo: Bool) {
        self.demo = demo
        headphones = demo ? .demo : nil
    }

    func refresh() {
        perform(.init(address: address, deviceType: deviceType))
    }

    func update(_ control: String, _ value: SettingValue) {
        guard let headphones, !isBusy else { return }
        if demo {
            updateDemo(control, value)
        } else {
            perform(.init(address: address, deviceType: deviceType, control: control,
                          value: value, previous: headphones))
        }
    }

    private func perform(_ request: BridgeRequest) {
        guard !demo, !isBusy else { return }
        isBusy = true
        message = nil
        Task {
            defer { isBusy = false }
            do {
                let reply = try await Task.detached(priority: .userInitiated) { try runBridge(request) }.value
                guard let snapshot = reply.snapshot else {
                    throw BridgeError(message: reply.error ?? "The headphones returned no status.")
                }
                headphones = snapshot
                address = reply.address
                deviceType = reply.deviceType
                message = reply.warning
            } catch {
                headphones = nil
                address = nil
                deviceType = nil
                message = error.localizedDescription
            }
        }
    }

    private func updateDemo(_ control: String, _ value: SettingValue) {
        guard var device = headphones else { return }
        switch (control, value) {
        case ("mode", .text(let value)): device.mode = device.profiles?.first { $0.command == value }?.id
        case ("anr", .text(let value)): device.anr = value
        case ("noise", .number(let value)): device.audio?.cncLevel = value
        case ("spatial", .text(let value)): device.audio?.spatial = ["off", "room", "head"].firstIndex(of: value) ?? 0
        case ("wind", .toggle(let value)): device.audio?.windBlock = value
        case ("anc", .toggle(let value)): device.audio?.ancToggle = value
        case ("eq", .bands(let values)):
            device.eq = device.eq?.map { band in
                var band = band
                band.value = values[band.id]
                return band
            }
        case ("sidetone", .text(let value)): device.sidetone = value
        case ("multipoint", .toggle(let value)): device.multipoint = value
        case ("autoPause", .toggle(let value)): device.autoPause = value
        case ("autoAnswer", .toggle(let value)): device.autoAnswer = value
        case ("prompts", .toggle(let value)): device.prompts = value
        default: return
        }
        headphones = device
    }
}
