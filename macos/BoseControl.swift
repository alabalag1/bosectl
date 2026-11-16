import SwiftUI

private let accent = Color(red: 0.75, green: 0.93, blue: 0.62)
private let surface = Color(red: 0.11, green: 0.13, blue: 0.12)
private let canvas = Color(red: 0.065, green: 0.077, blue: 0.069)

@main
struct BoseControlApp: App {
    @StateObject private var store = HeadphoneStore(demo: CommandLine.arguments.contains("--demo"))

    var body: some Scene {
        WindowGroup("Bose Control", id: "dashboard") {
            Dashboard(store: store)
                .frame(minWidth: 790, minHeight: 560)
                .preferredColorScheme(.dark)
                .tint(accent)
        }
        .defaultSize(width: 980, height: 740)
        .commands {
            CommandMenu("Headphones") {
                Button("Refresh Status", action: store.refresh)
                    .keyboardShortcut("r")
                    .disabled(store.isBusy || store.demo)
            }
        }
    }
}

private enum Page: String, CaseIterable {
    case listening = "Listening"
    case equalizer = "Equalizer"
    case device = "Device"

    var icon: String {
        switch self {
        case .listening: "waveform"
        case .equalizer: "slider.horizontal.3"
        case .device: "gearshape"
        }
    }
}

private struct Dashboard: View {
    @ObservedObject var store: HeadphoneStore
    @ViewState private var page = Page.listening
    @ViewState private var started = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let device = store.headphones {
                        hero(device)
                        if let message = store.message {
                            Label(message, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                        if !device.unavailable.isEmpty {
                            Label("Couldn’t read \(device.unavailable.joined(separator: ", ")). Use Refresh to retry.",
                                  systemImage: "info.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Group {
                            switch page {
                            case .listening: listening(device)
                            case .equalizer:
                                if let bands = device.eq {
                                    Equalizer(bands: bands, update: store.update)
                                } else {
                                    empty("Equalizer unavailable", "This device is not reporting three EQ bands.",
                                          icon: "slider.horizontal.3")
                                }
                            case .device: settings(device)
                            }
                        }
                        .disabled(store.isBusy)
                    } else {
                        empty(store.isBusy ? "Looking for headphones" : "Connect your headphones",
                              store.message ?? "Pair your Bose headphones in System Settings → Bluetooth.",
                              icon: store.isBusy ? "headphones" : "bolt.horizontal.circle")
                    }
                }
                .frame(maxWidth: 970, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .background(canvas)
        .task {
            guard !started else { return }
            started = true
            store.refresh()
        }
        .onChange(of: store.headphones?.eq != nil) { _, hasEQ in
            if !hasEQ && page == .equalizer { page = .listening }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(accent)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Bose Control").font(.headline)
            }
            .padding(.bottom, 23)
            ForEach(Page.allCases, id: \.self) { item in
                if item != .equalizer || store.headphones?.eq != nil {
                    Button {
                        page = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 13, weight: page == item ? .semibold : .medium))
                            .foregroundStyle(page == item ? accent : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(page == item ? accent.opacity(0.11) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(store.headphones != nil ? accent : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(store.demo ? "Demo device" : store.headphones != nil ? "Device available" : "No device")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 190)
        .background(surface.opacity(0.7))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(page.rawValue)
                .font(.system(size: 28, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if store.isBusy {
                ProgressView().controlSize(.small).accessibilityLabel("Communicating with headphones")
            }
            Button(action: store.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(store.isBusy || store.demo)
        }
    }

    private func hero(_ device: Headphones) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 11) {
                Text(device.title)
                    .font(.system(size: 31, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if device.model != device.title {
                    Text(device.model).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let battery = device.battery {
                        badge("\(battery)%", icon: battery < 20 ? "battery.25percent" : "battery.75percent")
                            .accessibilityLabel("Battery \(battery) percent")
                    }
                    if let mode = device.activeMode {
                        badge(mode, icon: "waveform")
                    }
                }
            }
            Spacer(minLength: 0)
            ZStack {
                ForEach([88.0, 114, 140], id: \.self) { size in
                    Circle().strokeBorder(accent.opacity(0.13), lineWidth: 1)
                        .frame(width: size, height: size)
                }
                Image(systemName: "headphones")
                    .font(.system(size: 53, weight: .light))
                    .foregroundStyle(accent)
            }
            .frame(width: 154)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(minHeight: 175)
        .background(
            LinearGradient(colors: [surface, Color(red: 0.16, green: 0.22, blue: 0.15)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21).strokeBorder(accent.opacity(0.15))
        }
    }

    private func badge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func listening(_ device: Headphones) -> some View {
        if let profiles = device.profiles {
            Panel("Listening modes") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    ForEach(profiles) { mode in
                        let selected = mode.id == device.mode
                        Button {
                            store.update("mode", .text(mode.command))
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: mode.icon).font(.system(size: 17))
                                Text(mode.name).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(selected ? accent : .primary)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(selected ? accent.opacity(0.12) : .white.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 11))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(selected ? accent.opacity(0.45) : .white.opacity(0.07))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selected)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        if let audio = device.audio {
            Panel("Noise control") {
                NoiseSlider(level: audio.cncLevel) { store.update("noise", .number($0)) }
                    .disabled(!audio.ancToggle || audio.windBlock)
                Divider()
                toggle("Noise cancellation", audio.ancToggle, control: "anc")
                toggle("Wind block", audio.windBlock, control: "wind")
            }
            Panel("Immersive audio") {
                optionPicker("Immersive audio", current: ["off", "room", "head"][safe: audio.spatial] ?? "",
                             options: [("Off", "off"), ("Still", "room"), ("Motion", "head")], control: "spatial")
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
        } else if let anr = device.anr {
            Panel("Noise cancellation") {
                optionPicker("Noise cancellation", current: anr,
                             options: [("Off", "off"), ("Low", "low"), ("Wind", "wind"), ("High", "high")],
                             control: "anr")
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func settings(_ device: Headphones) -> some View {
        Panel("Headphones") {
            LabeledContent("Model", value: device.model)
            if let firmware = device.firmware, !firmware.isEmpty {
                LabeledContent("Firmware", value: firmware)
            }
        }
        .padding(.bottom, 12)
        Panel("Preferences") {
            if let sidetone = device.sidetone {
                optionPicker("Sidetone", current: sidetone,
                             options: [("Off", "off"), ("Low", "low"), ("Medium", "medium"), ("High", "high")],
                             control: "sidetone")
            }
            toggle("Multipoint", device.multipoint, control: "multipoint")
            toggle("Auto-pause", device.autoPause, control: "autoPause")
            toggle("Auto-answer calls", device.autoAnswer, control: "autoAnswer")
            toggle("Voice prompts", device.prompts, control: "prompts")
        }
    }

    private func optionPicker(_ title: String, current: String, options: [(String, String)],
                              control: String) -> some View {
        Picker(title, selection: Binding(get: { current }, set: { store.update(control, .text($0)) })) {
            if !options.contains(where: { $0.1 == current }) {
                Text("Unknown").tag(current)
            }
            ForEach(options, id: \.1) { label, value in
                Text(label).tag(value)
            }
        }
    }

    @ViewBuilder
    private func toggle(_ title: String, _ value: Bool?, control: String) -> some View {
        if let value {
            Toggle(title, isOn: Binding(get: { value }, set: { store.update(control, .toggle($0)) }))
                .toggleStyle(.switch)
        }
    }

    private func empty(_ title: String, _ description: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(description))
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07)) }
    }
}

private struct NoiseSlider: View {
    let level: Int
    let update: (Int) -> Void
    @ViewState private var draft: Double?

    var body: some View {
        let strength = 10 - min(10, max(0, level))
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Cancellation strength").font(.subheadline)
                Spacer()
                Text("\(Int(draft ?? Double(strength)))/10")
                    .monospacedDigit()
                    .foregroundStyle(accent)
                if let draft, Int(draft) != strength {
                    Button("Apply") {
                        update(10 - Int(draft))
                        self.draft = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Slider(value: Binding(get: { draft ?? Double(strength) }, set: { draft = $0 }),
                   in: 0...10, step: 1) {
                Text("Cancellation strength")
            }
            .labelsHidden()
            .accessibilityValue("\(Int(draft ?? Double(strength))) of 10")
            HStack {
                Text("More surroundings")
                Spacer()
                Text("More cancellation")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: level) { _, _ in draft = nil }
    }
}

private struct Equalizer: View {
    let bands: [EQBand]
    let update: (String, SettingValue) -> Void
    @ViewState private var draft: [Int: Int] = [:]

    private var values: [Int] { bands.map { draft[$0.id] ?? $0.value } }

    var body: some View {
        Panel("Three-band equalizer") {
            ForEach(bands) { band in
                let value = draft[band.id] ?? band.value
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(band.name.capitalized).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(value > 0 ? "+\(value)" : "\(value)")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    if band.minimum < band.maximum {
                        Slider(value: Binding(
                            get: { Double(value) },
                            set: { draft[band.id] = Int($0) }
                        ), in: Double(band.minimum)...Double(band.maximum), step: 1) {
                            Text(band.name.capitalized)
                        }
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Button("Flat") {
                    draft = Dictionary(uniqueKeysWithValues: bands.map { ($0.id, max($0.minimum, min(0, $0.maximum))) })
                }
                Spacer()
                Button("Apply EQ") {
                    update("eq", .bands(values))
                    draft = [:]
                }
                .buttonStyle(.borderedProminent)
                .disabled(values == bands.map(\.value))
            }
        }
        .onChange(of: bands.map(\.value)) { _, _ in draft = [:] }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Use SwiftUI's State storage directly to support SDKs with and without the State macro.
@propertyWrapper
private struct ViewState<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
}
