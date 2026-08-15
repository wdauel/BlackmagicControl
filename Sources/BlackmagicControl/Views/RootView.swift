import SwiftUI

struct RootView: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: Theme.gutter) {
                CameraTabBar()
                Rectangle().fill(Theme.record).frame(height: 2)   // ARRI armed line
                if let sel = manager.selected {
                    CameraScreen(cam: sel).id(sel.id)
                } else {
                    emptyState
                }
            }
            .padding(Theme.gutter)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No cameras. Tap + to add one.")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Camera tab bar (multi-phone switcher)

struct CameraTabBar: View {
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        HStack(spacing: 8) {
            ForEach(manager.cameras) { cam in
                CameraTab(cam: cam, selected: cam.id == manager.selectedID) { manager.select(cam) }
                    .contextMenu {
                        Button(role: .destructive) { manager.remove(cam) } label: {
                            Label("Remove Camera", systemImage: "trash")
                        }
                    }
            }
            Button { manager.addCamera() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Theme.textSecondary)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke, lineWidth: 1))
            }.buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 40)
    }
}

struct CameraTab: View {
    @ObservedObject var cam: CameraController
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cam.name).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    Text(cam.host).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                if cam.isRecording {
                    Circle().fill(Theme.record).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? Theme.panel : Theme.inset.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? statusColor.opacity(0.7) : Theme.stroke, lineWidth: selected ? 1.5 : 1)
            )
        }.buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch cam.connection {
        case .connected:    return Theme.accent
        case .connecting:   return Theme.amber
        case .disconnected: return Theme.textTertiary
        case .failed:       return Theme.record
        }
    }
}

// MARK: - Per-camera screen

struct CameraScreen: View {
    @ObservedObject var cam: CameraController

    var body: some View {
        VStack(spacing: Theme.gutter) {
            TopBar()
            if cam.isConnected {
                DashboardView()
            } else {
                ConnectView()
            }
        }
        .environmentObject(cam)
    }
}

// MARK: - Top bar (selected camera header)

struct TopBar: View {
    @EnvironmentObject var cam: CameraController
    @EnvironmentObject var manager: CameraManager

    var body: some View {
        HStack(spacing: 12) {
            CameraTagBadge(cam: cam, manager: manager)

            TextField("Camera", text: $cam.name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 150)
                .onSubmit { manager.save() }

            connectionPill

            if cam.isConnected && cam.liveConnected {
                StatusPill(text: "LIVE", color: Theme.blue)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(cam.host):\(String(cam.port))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text("v\(AppInfo.version) · by \(AppInfo.author)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
            }
            if cam.isConnected {
                Button { Task { await cam.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(TopBarButton())
                Button { cam.disconnect() } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(TopBarButton())
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }

    @ViewBuilder private var connectionPill: some View {
        switch cam.connection {
        case .connected:    EmptyView()   // LIVE pill covers the connected state
        case .connecting:   StatusPill(text: "CONNECTING", color: Theme.amber)
        case .disconnected: StatusPill(text: "OFFLINE", color: Theme.textTertiary)
        case .failed:       StatusPill(text: "NO LINK", color: Theme.record)
        }
    }
}

// MARK: - Camera tag badge (editable letter + color)

/// The A/B/C… camera-ID chip in the top bar. Tapping opens a popover to choose
/// any letter A–Z and a color (swatches + full picker). Persists via the manager.
struct CameraTagBadge: View {
    @ObservedObject var cam: CameraController
    let manager: CameraManager

    @State private var show = false

    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private let swatches: [UInt32] = [
        0xE5383B, 0xFF7A1A, 0xFFB020, 0x2FB84F, 0x39C7FF, 0x2E6FE0, 0xA855F7, 0xEC4899, 0xF4F4F5
    ]
    private let letterColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        Button { show = true } label: {
            Text(cam.letter)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(cam.tagColor)
                .frame(width: 22, height: 22)
                .background(cam.tagColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(cam.tagColor.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("CAMERA LETTER").controlLabelStyle()
                LazyVGrid(columns: letterColumns, spacing: 6) {
                    ForEach(alphabet, id: \.self) { letter in
                        let active = letter == cam.letter
                        Button { cam.letter = letter; manager.save() } label: {
                            Text(letter)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(active ? .black : Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(active ? cam.tagColor : Theme.inset,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(active ? .clear : Theme.stroke, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }

                Divider().overlay(Theme.stroke)

                HStack {
                    Text("COLOR").controlLabelStyle()
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { cam.tagColor },
                        set: { cam.tagColorHex = $0.hexValue; manager.save() }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
                LazyVGrid(columns: swatchColumns, spacing: 8) {
                    ForEach(swatches, id: \.self) { hex in
                        let active = hex == cam.tagColorHex
                        Button { cam.tagColorHex = hex; manager.save() } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .frame(maxWidth: .infinity)
                                .overlay(Circle().strokeBorder(.white.opacity(active ? 0.9 : 0.15),
                                                               lineWidth: active ? 2 : 1)
                                    .frame(width: 24, height: 24))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(16).frame(width: 264).background(Theme.panel)
        }
    }
}

struct TopBarButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 30, height: 26)
            .foregroundStyle(Theme.textSecondary)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Connect screen

struct ConnectView: View {
    @EnvironmentObject var cam: CameraController
    @EnvironmentObject var manager: CameraManager
    @State private var portText = ""

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "video.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text("Connect \(cam.name)")
                    .font(.system(size: 18, weight: .bold))
                Text("Enter the address shown in the Blackmagic Camera app.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 8) {
                    field("Host / IP", text: $cam.host, width: 200)
                    field("Port", text: $portText, width: 80)
                        .onAppear { portText = String(cam.port) }
                }

                Button {
                    cam.port = Int(portText) ?? 4444
                    manager.save()
                    cam.connect()
                } label: {
                    Text(cam.connection == .connecting ? "Connecting…" : "Connect")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 288, height: 40)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(cam.connection == .connecting)

                if case .failed(let msg) = cam.connection {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.record)
                        .multilineTextAlignment(.center)
                        .frame(width: 288)
                }
            }
            .padding(34)
            .frame(width: 380)
            .panelStyle()
            Spacer()
        }
    }

    private func field(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).controlLabelStyle()
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .padding(.horizontal, 10).frame(width: width, height: 34)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
}
