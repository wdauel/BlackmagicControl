import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var cam: CameraController

    // Kelvin quick-pick presets for the White Balance popover.
    private let kelvinPresets = [3200, 4300, 5000, 5600, 6000, 6500]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.gutter) {

                // Top strip: timecode • REC
                HStack(spacing: Theme.gutter) {
                    timecodeCard
                    recCard
                }
                .fixedSize(horizontal: false, vertical: true)

                // Media / storage
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gutter), count: 4),
                          spacing: Theme.gutter) {
                    infoTile("Media", cam.storageVolume)
                    infoTile("Record Time", cam.remainingRecordTime > 0 ? "\(cam.remainingRecordTime)" : "—", unit: "min")
                    infoTile("Clips", "\(cam.clipCount)")
                    levelTile
                }

                // Exposure tiles — ISO, Shutter (lock), White Balance (lock), Auto Exposure
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gutter), count: 4),
                          spacing: Theme.gutter) {
                    isoTile
                    shutterTile
                    whiteBalanceTile
                    autoExposureTile
                }

                // Focus (2/3) + Lens + Iris in one row
                focusRow

                // Codec • Format • FPS
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gutter), count: 3),
                          spacing: Theme.gutter) {
                    PickerTile(caption: "Recording Codec", value: cam.codecFull, valueSize: 16,
                               options: cam.supportedCodecs, current: cam.codecFull,
                               onSelect: { cam.setCodec($0) })
                    formatTile
                    PickerTile(caption: "Frame Rate", value: cam.currentFPS, unit: "fps", valueSize: 24,
                               options: cam.availableFPS(for: cam.currentResolution), current: cam.currentFPS,
                               onSelect: { cam.setFPS($0) })
                }

                // Monitoring + recording tools
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gutter), count: 6),
                          spacing: Theme.gutter) {
                    toggleTile("False Color", cam.falseColor) { cam.setFalseColor(!cam.falseColor) }
                    toggleTile("Focus Assist", cam.focusAssist) { cam.setFocusAssist(!cam.focusAssist) }
                    toggleTile("Zebra", cam.zebra) { cam.setZebra(!cam.zebra) }
                    toggleTile("Frame Guide", cam.frameGuide) { cam.setFrameGuide(!cam.frameGuide) }
                    PickerTile(caption: "Guide Ratio", value: cam.frameGuideRatio, valueSize: 17,
                               options: cam.frameGuidePresets, current: cam.frameGuideRatio,
                               onSelect: { cam.setFrameGuideRatio($0) })
                    toggleTile("Proxy Rec", cam.proxyRecording) { cam.setProxyRecording(!cam.proxyRecording) }
                }

                // Slate — scene / take / reel
                slateCard

                // Presets
                presetsCard
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { errorToast }
    }

    // MARK: Top strip

    private var timecodeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timecode").controlLabelStyle()
            TimecodeView(timecode: cam.timecode, running: cam.isRecording)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                StatusPill(text: cam.isRecording ? "RECORDING" : "STANDBY",
                           color: cam.isRecording ? Theme.record : Theme.accent,
                           filled: cam.isRecording)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .panelStyle()
    }

    private var recCard: some View {
        VStack {
            RecButton(isRecording: cam.isRecording) { cam.toggleRecord() }
                .frame(width: 116, height: 116)
        }
        .frame(width: 170, height: 150)
        .panelStyle()
    }

    /// Level tile — roll / pitch readout from the motion sensor.
    private var levelTile: some View {
        Tile(caption: "Level") {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Roll  %+.0f°", cam.horizonRoll))
                Text(String(format: "Pitch %+.0f°", cam.horizonPitch))
            }
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(cam.horizonAvailable ? Theme.textPrimary : Theme.textTertiary)
        }
    }

    // MARK: Shutter (compact lockable tile + popover editor)

    private var shutterTile: some View {
        LockTile(caption: "Shutter",
                 value: String(format: "%.1f°", cam.shutterAngle),
                 subValue: shutterSpeedText,
                 locked: Binding(get: { cam.shutterLocked }, set: { cam.shutterLocked = $0 })) {
            shutterEditor
        }
    }

    /// Nominal 1/x exposure time from shutter angle and current frame rate.
    private var shutterSpeedText: String? {
        guard let fps = Double(cam.frameRate), fps > 0, cam.shutterAngle > 0 else { return nil }
        let denom = fps * 360 / cam.shutterAngle
        return "1/\(Int(denom.rounded()))"
    }

    private var shutterEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SHUTTER ANGLE").controlLabelStyle()
                Spacer()
                Text(shutterLabel(cam.shutterAngle))
                    .font(.readout(22)).foregroundStyle(Theme.textPrimary)
            }

            VStack(spacing: 5) {
                // Tick marks, one per stop (equally spaced to match the stepped slider)
                GeometryReader { geo in
                    let inset: CGFloat = 11
                    let usable = max(geo.size.width - inset * 2, 1)
                    ForEach(shutterStops.indices, id: \.self) { i in
                        let frac = CGFloat(i) / CGFloat(shutterStops.count - 1)
                        let active = i == nearestShutterIndex(cam.shutterAngle)
                        Rectangle()
                            .fill(active ? Theme.accent : Theme.textTertiary)
                            .frame(width: active ? 2 : 1, height: active ? 9 : 6)
                            .offset(x: inset + frac * usable - (active ? 1 : 0.5))
                    }
                }
                .frame(height: 9)

                Slider(value: Binding(
                            get: { Double(nearestShutterIndex(cam.shutterAngle)) },
                            set: { cam.setShutterAngle(shutterStops[Int($0.rounded())]) }),
                       in: 0...Double(shutterStops.count - 1), step: 1)
                    .tint(Theme.accent)
            }

            HStack {
                Text("\(shutterLabel(shutterStops.first!))").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(shutterLabel(shutterStops.last!))").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
        }
        .task { await cam.refreshSupportedExposure() }
    }

    /// Shutter-angle stops the slider snaps to — from the camera when available,
    /// otherwise a sensible default.
    private var shutterStops: [Double] {
        cam.supportedShutterAngles.isEmpty
            ? [1.35, 2.7, 5.4, 10.8, 21.6, 43.2, 45, 54, 86.4, 90, 108, 112.5, 180, 216, 225, 327.27, 360]
            : cam.supportedShutterAngles
    }
    private func nearestShutterIndex(_ angle: Double) -> Int {
        var best = 0, bestDiff = Double.greatestFiniteMagnitude
        for (i, v) in shutterStops.enumerated() {
            let d = abs(v - angle)
            if d < bestDiff { bestDiff = d; best = i }
        }
        return best
    }
    private func shutterLabel(_ deg: Double) -> String {
        deg == deg.rounded() ? String(format: "%.0f°", deg) : String(format: "%.1f°", deg)
    }

    // MARK: Exposure tiles

    private var isoTile: some View {
        LockTile(caption: "Exposure Index",
                 value: "\(cam.iso)",
                 unit: "EI",
                 locked: Binding(get: { cam.isoLocked }, set: { cam.isoLocked = $0 })) {
            ISOEditor(cam: cam)
        }
    }

    private var irisTile: some View {
        Tile(caption: "Iris", locked: true) {
            ReadoutTile(value: String(format: "ƒ%.1f", cam.irisFStop), label: "", accent: Theme.textPrimary, size: 22)
        }
    }

    private var lensTile: some View {
        Tile(caption: "Lens", locked: true) {
            ReadoutTile(value: "\(cam.focalLength)", unit: "mm", label: "", size: 22)
        }
    }

    // MARK: Format tile (friendly resolution names)

    /// Marketing names for the common capture resolutions; unknown sizes fall
    /// back to the raw "WxH" string.
    private func formatName(_ res: String) -> String {
        switch res {
        case "4032x3024": return "Open Gate"
        case "3840x2160": return "UHD"
        case "1920x1080": return "HD"
        default:          return res
        }
    }

    /// Dropdown label — name followed by the numbers, e.g. "UHD  3840x2160".
    private func formatLabel(_ res: String) -> String {
        let name = formatName(res)
        return name == res ? res : "\(name)  \(res)"
    }

    private var formatTile: some View {
        let res = cam.currentResolution
        let name = formatName(res)
        return PickerTile(caption: "Format",
                          value: name,
                          subValue: name == res ? nil : res,
                          valueSize: 20,
                          options: cam.availableResolutions.map { formatLabel($0) },
                          current: formatLabel(res),
                          onSelect: { picked in
                              if let match = cam.availableResolutions.first(where: { formatLabel($0) == picked }) {
                                  cam.setResolution(match)
                              }
                          })
    }

    // MARK: White balance (compact lockable tile + popover editor)

    private var whiteBalanceTile: some View {
        LockTile(caption: "White Balance",
                 value: "\(cam.whiteBalance)",
                 unit: "K",
                 subValue: "tint \(cam.tint > 0 ? "+" : "")\(cam.tint)",
                 locked: Binding(get: { cam.wbLocked }, set: { cam.wbLocked = $0 })) {
            wbEditor
        }
    }

    private var wbEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WHITE BALANCE").controlLabelStyle()
                Spacer()
                Button { cam.autoWhiteBalance() } label: {
                    Text("AWB").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.amber, in: Capsule())
                }.buttonStyle(.plain)
            }
            sliderRow(label: "TEMP", valueText: "\(cam.whiteBalance) K", gradient: .temperature,
                      value: Binding(get: { Double(cam.whiteBalance) }, set: { cam.whiteBalance = Int($0) }),
                      range: 2500...10000, commit: { cam.setWhiteBalance(cam.whiteBalance) })
            sliderRow(label: "TINT", valueText: "\(cam.tint > 0 ? "+" : "")\(cam.tint)", gradient: .tint,
                      value: Binding(get: { Double(cam.tint) }, set: { cam.tint = Int($0) }),
                      range: -50...50, commit: { cam.setTint(cam.tint) })
            HStack(spacing: 5) {
                ForEach(kelvinPresets, id: \.self) { k in
                    Button { cam.setWhiteBalance(k) } label: {
                        Text(verbatim: "\(k)K")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(cam.whiteBalance == k ? .black : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(cam.whiteBalance == k ? Theme.amber : Theme.inset, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Auto exposure (compact menu tile)

    private var autoExposureTile: some View {
        PickerTile(caption: "Auto Exposure",
                   value: aeLabel(cam.aeMode),
                   valueSize: 22,
                   options: ["Off", "Continuous", "One-Shot"],
                   current: aeLabel(cam.aeMode),
                   onSelect: { cam.setAutoExposure(aeMode(fromLabel: $0)) })
    }

    private func aeLabel(_ mode: String) -> String {
        switch mode {
        case "Continuous": return "Continuous"
        case "OneShot":    return "One-Shot"
        default:            return "Off"
        }
    }
    private func aeMode(fromLabel label: String) -> String {
        switch label {
        case "Continuous": return "Continuous"
        case "One-Shot":   return "OneShot"
        default:            return "Off"
        }
    }

    // MARK: Focus row (compact FOCUS tile 2/3 + Lens + Iris)

    private var focusRow: some View {
        GeometryReader { geo in
            let g = Theme.gutter
            // Match the 6-column grid below: focus spans cols 1–4, lens = col 5,
            // iris = col 6, so their edges line up vertically with the tiles under them.
            let colW = max((geo.size.width - 5 * g) / 6, 1)
            HStack(spacing: g) {
                focusTile.frame(width: colW * 4 + g * 3)
                lensTile.frame(width: colW)
                irisTile.frame(width: colW)
            }
        }
        .frame(height: 78)
    }

    private var focusTile: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Focus").controlLabelStyle()
                Spacer()
                afButton
            }
            HStack(spacing: 10) {
                Text(String(format: "%.3f", cam.focusNormalised))
                    .font(.readout(20)).foregroundStyle(Theme.textPrimary)
                Slider(value: Binding(get: { cam.focusNormalised },
                                      set: { cam.setFocus(normalised: $0) }),
                       in: 0...0.999)
                    .tint(Theme.accent)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
    }

    /// AF trigger — grey when idle, green only while an autofocus pass is running.
    private var afButton: some View {
        Button { cam.autoFocus() } label: {
            Text("AF")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(cam.afActive ? .black : Theme.textTertiary)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(cam.afActive ? Theme.accent : Theme.inset, in: Capsule())
                .overlay(Capsule().strokeBorder(cam.afActive ? .clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: cam.afActive)
    }


    // MARK: Slate card

    private var slateCard: some View {
        PanelCard(title: "SLATE", accent: Theme.accent, collapsible: true) {
            HStack(alignment: .top, spacing: Theme.gutter) {
                VStack(spacing: 8) {
                    Text("SCENE").controlLabelStyle()
                    SlateSceneField(cam: cam)
                }
                .frame(maxWidth: .infinity)
                slateStepper("TAKE", value: cam.slateTake) { cam.setSlateTake($0) }
                slateStepper("REEL", value: cam.slateReel) { cam.setSlateReel($0) }
            }

            slateDivider("PROJECT")
            LazyVGrid(columns: slateFieldColumns, spacing: 10) {
                SlateField(label: "PRODUCTION", value: cam.slateProjectName) { cam.setSlateProjectName($0) }
                SlateField(label: "DIRECTOR", value: cam.slateDirector) { cam.setSlateDirector($0) }
                SlateField(label: "CAMERA", value: cam.slateCamera) { cam.setSlateCamera($0) }
                SlateField(label: "CAMERA OPERATOR", value: cam.slateCameraOperator) { cam.setSlateCameraOperator($0) }
            }

            slateDivider("LENS DATA")
            LazyVGrid(columns: slateFieldColumns, spacing: 10) {
                SlateField(label: "LENS TYPE", value: cam.slateLensType, placeholder: "e.g. EF 50mm") { cam.setSlateLensType($0) }
                SlateField(label: "FILTER", value: cam.slateFilter, placeholder: "e.g. ND2") { cam.setSlateFilter($0) }
                SlateField(label: "IRIS", value: cam.slateIris, placeholder: "auto") { cam.setSlateIris($0) }
                SlateField(label: "FOCAL LENGTH", value: cam.slateFocalLength, placeholder: "auto") { cam.setSlateFocalLength($0) }
                SlateField(label: "DISTANCE", value: cam.slateDistance, placeholder: "e.g. 13'") { cam.setSlateDistance($0) }
            }
            Text("Iris and focal length are typically filled in automatically by the camera.")
                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
    }

    private var slateFieldColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.gutter), count: 2)
    }

    private func slateDivider(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(Theme.textSecondary)
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private func slateStepper(_ label: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 8) {
            Text(label).controlLabelStyle()
            HStack(spacing: 10) {
                stepButton("minus") { set(value - 1) }
                Text("\(value)")
                    .font(.readout(24)).foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 36)
                stepButton("plus") { set(value + 1) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.inset, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Presets card

    private var presetsCard: some View {
        PanelCard(title: "PRESETS", accent: Theme.accent,
                  trailing: AnyView(SavePresetButton(cam: cam))) {
            if cam.presets.isEmpty {
                Text("No presets saved. Tap Save to store the current camera state.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(cam.presets, id: \.self) { name in
                        let active = name == cam.activePreset
                        Button { cam.applyPreset(name) } label: {
                            Text(presetLabel(name))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(active ? .black : Theme.textPrimary)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(active ? Theme.accent : Theme.inset,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? .clear : Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { cam.deletePreset(name) } label: {
                                Label("Delete Preset", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Presets are stored as "Name.cset"; hide the extension in the UI.
    private func presetLabel(_ name: String) -> String {
        name.lowercased().hasSuffix(".cset") ? String(name.dropLast(5)) : name
    }

    // MARK: Small builders

    private func infoTile(_ caption: String, _ value: String, unit: String? = nil) -> some View {
        Tile(caption: caption) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.unit).foregroundStyle(Theme.textTertiary) }
            }
        }
    }

    /// A tappable on/off tile (ON = green), for monitoring & recording toggles.
    private func toggleTile(_ caption: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        Tile(caption: caption, action: action) {
            Text(isOn ? "ON" : "OFF")
                .font(.readout(22))
                .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
        }
        .overlay(alignment: .topLeading) {
            if isOn {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).padding(8)
            }
        }
    }

    private func sliderRow(label: String, valueText: String, gradient: Gradient,
                           value: Binding<Double>, range: ClosedRange<Double>,
                           commit: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label).controlLabelStyle().frame(width: 44, alignment: .leading)
            GradientSlider(value: value, range: range, gradient: gradient, onCommit: commit)
            Text(valueText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    @ViewBuilder private var errorToast: some View {
        if let err = cam.lastError {
            Text(err)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.record.opacity(0.9), in: Capsule())
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task { try? await Task.sleep(for: .seconds(3)); cam.lastError = nil }
                }
        }
    }
}


// MARK: - ISO editor (stepped slider, popover content for the ISO tile)

struct ISOEditor: View {
    @ObservedObject var cam: CameraController

    /// The camera's own supported ISO stops (lens-aware); fallback if not loaded.
    private var isoStops: [Int] {
        cam.supportedISOs.isEmpty ? [100, 200, 400, 800, 1600, 3200] : cam.supportedISOs
    }

    private func nearestIndex(_ v: Int) -> Int {
        var best = 0, bestDiff = Int.max
        for (i, s) in isoStops.enumerated() {
            let d = abs(s - v)
            if d < bestDiff { bestDiff = d; best = i }
        }
        return best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EXPOSURE INDEX").controlLabelStyle()
                Spacer()
                Text(verbatim: "\(cam.iso) EI")
                    .font(.readout(22)).foregroundStyle(Theme.textPrimary)
            }

            VStack(spacing: 5) {
                GeometryReader { geo in
                    let inset: CGFloat = 11
                    let usable = max(geo.size.width - inset * 2, 1)
                    let activeIdx = nearestIndex(cam.iso)
                    ForEach(isoStops.indices, id: \.self) { i in
                        let frac = CGFloat(i) / CGFloat(isoStops.count - 1)
                        let active = i == activeIdx
                        Rectangle()
                            .fill(active ? Theme.accent : Theme.textTertiary)
                            .frame(width: active ? 2 : 1, height: active ? 9 : 6)
                            .offset(x: inset + frac * usable - (active ? 1 : 0.5))
                    }
                }
                .frame(height: 9)

                Slider(value: Binding(
                            get: { Double(nearestIndex(cam.iso)) },
                            set: { cam.setISO(isoStops[Int($0.rounded())]) }),
                       in: 0...Double(isoStops.count - 1), step: 1)
                    .tint(Theme.accent)
            }

            HStack {
                Text(verbatim: "\(isoStops.first!)")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(verbatim: "\(isoStops.last!)")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(Theme.textTertiary)
            }
        }
        .task { await cam.refreshSupportedExposure() }
    }
}

// MARK: - Save preset button

/// "Save" pill that opens a popover to name and store the current camera state.
struct SavePresetButton: View {
    @ObservedObject var cam: CameraController
    @State private var show = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        Button { name = ""; show = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                Text("Save")
            }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SAVE PRESET").controlLabelStyle()
                Text("Stores the current camera state as a new preset.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                TextField("Preset name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .onSubmit(save)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Cancel") { show = false }.buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary).font(.system(size: 12, weight: .medium))
                    Button(action: save) {
                        Text("Save").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16).frame(width: 280).background(Theme.panel)
            .onAppear { focused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        cam.savePreset(trimmed)
        show = false
    }
}

// MARK: - Slate text field

/// A labeled text field for slate metadata. Keeps a local buffer + focus guard so
/// the background poll can't clobber what the operator is typing; commits on
/// Return / focus loss.
struct SlateField: View {
    let label: String
    let value: String
    var placeholder: String = ""
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).controlLabelStyle()
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
                .onAppear { text = value }
                .onChange(of: value) { _, new in if !focused { text = new } }
        }
    }

    private func commit() {
        if text != value { onCommit(text) }
    }
}

// MARK: - Slate scene field

/// Editable scene text. Keeps a local buffer so a background poll doesn't clobber
/// what the operator is typing; commits to the camera on Return / focus loss.
struct SlateSceneField: View {
    @ObservedObject var cam: CameraController
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("1", text: $text)
            .textFieldStyle(.plain)
            .font(.readout(24))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textPrimary)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1))
            .onAppear { text = cam.slateScene }
            .onChange(of: cam.slateScene) { _, new in if !focused { text = new } }
    }

    private func commit() {
        let v = text.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, v != cam.slateScene { cam.setSlateScene(v) }
    }
}
