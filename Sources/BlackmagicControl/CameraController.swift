import SwiftUI
import Combine

/// Observable camera state + all control actions. Lives on the main actor so the
/// UI can bind directly; network calls hop to the shared `URLSession`.
@MainActor
final class CameraController: ObservableObject, Identifiable {

    enum Connection: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    // Identity + connection
    let id: UUID
    @Published var name: String
    @Published var host: String
    @Published var port: Int
    @Published var connection: Connection = .disconnected
    @Published var deviceName: String = "—"
    @Published var codec: String = "—"
    @Published var resolution: String = "—"
    @Published var frameRate: String = "—"
    @Published var lastError: String?

    init(id: UUID = UUID(), name: String, host: String, port: Int = 4444,
         letter: String = "A", tagColorHex: UInt32 = 0xE5383B) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.letter = letter
        self.tagColorHex = tagColorHex
    }

    // Video
    @Published var iso: Int = 400
    @Published var gain: Int = 0
    @Published var whiteBalance: Int = 5600
    @Published var tint: Int = 0
    @Published var shutterAngle: Double = 180
    @Published var shutterSpeed: Int? = nil
    @Published var shutterIsAngleScaled = false        // firmware scale (÷100) discovered on read
    @Published var ndStop: Double? = nil

    // Lens
    @Published var irisFStop: Double = 4.0
    @Published var irisNormalised: Double = 0.5
    @Published var focusNormalised: Double = 1.0
    @Published var afActive = false            // true briefly while an AF pass runs
    @Published var focalLength: Int = 24        // selected lens, in mm

    // Transport
    @Published var isRecording = false
    @Published var timecode: String = "00:00:00:00"

    // Presets
    @Published var presets: [String] = []
    @Published var activePreset: String?

    // Format
    @Published var codecFull: String = ""            // "Apple ProRes RAW HQ:High"
    @Published var videoFormatName: String = ""      // "3840x2160p29.97"
    @Published var supportedCodecs: [String] = []
    @Published var supportedVideoFormats: [String] = []

    // Device-supported exposure stops (authoritative — updates with lens/format)
    @Published var supportedISOs: [Int] = []
    @Published var supportedShutterAngles: [Double] = []

    // Dynamic range
    @Published var dynamicRange: String = ""
    @Published var supportedDynamicRanges: [String] = []

    // Recording tools
    @Published var proxyRecording = false

    // Monitoring / tools
    @Published var falseColor = false
    @Published var focusAssist = false
    @Published var zebra = false
    @Published var frameGuide = false
    @Published var frameGuideRatio = ""
    @Published var frameGuidePresets: [String] = []
    private var monitorDisplay = "Device"
    private var zebraRaw = ZebraValue(skinTone: ZebraBand(type: "None", level: nil, enabled: false),
                                      highlight: ZebraBand(type: nil, level: 85, enabled: false))

    // Auto exposure
    @Published var aeMode: String = "Off"            // Off | Continuous | OneShot

    // Per-control locks (UI affordance, like the app)
    @Published var shutterLocked = false
    @Published var wbLocked = false
    @Published var isoLocked = false

    // Color correction
    @Published var ccLift = ColorRGBL(red: 0, green: 0, blue: 0, luma: 0)
    @Published var ccGamma = ColorRGBL(red: 0, green: 0, blue: 0, luma: 0)
    @Published var ccGain = ColorRGBL(red: 1, green: 1, blue: 1, luma: 1)
    @Published var ccOffset = ColorRGBL(red: 0, green: 0, blue: 0, luma: 0)
    @Published var ccContrast = ContrastValue(pivot: 0.5, adjust: 1)
    @Published var ccColor = ColorValue(hue: 0, saturation: 1)
    @Published var ccLumaContribution: Double = 1

    // Audio (2 channels)
    @Published var audioInputs: [String] = ["None", "None"]
    @Published var audioLevels: [Double] = [1, 1]
    @Published var audioPhantom: [Bool] = [false, false]
    @Published var audioSupportedInputs: [String] = []

    // Media / storage
    @Published var storageVolume: String = "—"
    @Published var remainingRecordTime: Int = 0      // minutes
    @Published var remainingSpace: Int64 = 0
    @Published var clipCount: Int = 0

    // Camera tag (editable letter + color shown in the top bar)
    @Published var letter: String
    @Published var tagColorHex: UInt32
    var tagColor: Color { Color(hex: tagColorHex) }

    // Horizon / level (degrees; + roll = clockwise, + pitch = nose up)
    @Published var horizonRoll: Double = 0
    @Published var horizonPitch: Double = 0
    @Published var horizonAvailable = false

    // Slate (digital slate for the NEXT clip). Take auto-increment is forced on.
    @Published var slateScene = "1"
    @Published var slateTake = 1
    @Published var slateReel = 1
    // Slate — project block
    @Published var slateProjectName = ""
    @Published var slateDirector = ""
    @Published var slateCamera = ""
    @Published var slateCameraOperator = ""
    // Slate — lens block
    @Published var slateLensType = ""
    @Published var slateIris = ""
    @Published var slateFocalLength = ""
    @Published var slateDistance = ""
    @Published var slateFilter = ""

    private var client: BMDClient?
    private var pollTask: Task<Void, Never>?

    // Live event socket
    private let wsSession = URLSession(configuration: .ephemeral,
                                       delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
    private var wsTask: URLSessionWebSocketTask?
    @Published var liveConnected = false

    var isConnected: Bool { connection == .connected }

    // MARK: - Connection

    func connect() {
        connection = .connecting
        lastError = nil
        let c = BMDClient(host: host, port: port)
        client = c
        Task {
            do {
                let info = try await c.ping()
                deviceName = info.deviceName ?? info.model ?? "Blackmagic Camera"
                applySystem(info)
                connection = .connected
                await refreshAll()
                startPolling()
                startEventSocket()
            } catch {
                connection = .failed((error as? BMDError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func disconnect() {
        pollTask?.cancel(); pollTask = nil
        wsTask?.cancel(with: .goingAway, reason: nil); wsTask = nil
        liveConnected = false
        client = nil
        connection = .disconnected
    }

    // MARK: - Reads

    /// Pull the full state once (on connect / manual refresh). Sequential awaits
    /// keep everything on the main actor; on a LAN this is comfortably fast.
    func refreshAll() async {
        guard let c = client else { return }
        if let info = try? await c.ping() { applySystem(info) }
        if let v = try? await c.get(Endpoint.iso, as: ISOValue.self) { iso = v.iso }
        if let v = try? await c.get(Endpoint.whiteBalance, as: WhiteBalanceValue.self) { whiteBalance = v.whiteBalance }
        if let v = try? await c.get(Endpoint.whiteBalanceTint, as: WhiteBalanceTintValue.self) { tint = v.whiteBalanceTint }
        if let s = try? await c.get(Endpoint.shutter, as: ShutterValue.self) {
            if let raw = s.shutterAngle {
                shutterIsAngleScaled = raw > 360
                shutterAngle = ShutterAngle.degrees(from: raw)
            }
            shutterSpeed = s.shutterSpeed
        }
        if let i = try? await c.get(Endpoint.iris, as: IrisValue.self) {
            if let f = i.apertureStop { irisFStop = f }
            else if let n = i.apertureNumber { irisFStop = n / 100 }
            if let n = i.normalised { irisNormalised = n }
        }
        if let f = try? await c.get(Endpoint.focus, as: FocusValue.self) { focusNormalised = f.normalised }
        if let z = try? await c.get(Endpoint.zoom, as: ZoomValue.self), let mm = z.focalLength { focalLength = mm }
        if let r = try? await c.get(Endpoint.record, as: RecordState.self) { isRecording = r.recording }
        if let ae = try? await c.get(Endpoint.autoExposure, as: AutoExposureValue.self), let m = ae.mode { aeMode = m }

        // Format + supported lists
        if let cf = try? await c.get("/system/format", as: SystemFormat.self) {
            if let cc = cf.codec { codecFull = cc }
        }
        if let vf = try? await c.get(Endpoint.videoFormat, as: SystemInfo.VideoFormat.self), let n = vf.name { videoFormatName = n }
        if let sc = try? await c.get(Endpoint.supportedCodecs, as: SupportedCodecFormats.self) {
            supportedCodecs = sc.codecFormats.map(\.codec)
        }
        if let sv = try? await c.get(Endpoint.supportedVideos, as: SupportedVideoFormats.self) {
            supportedVideoFormats = sv.videoFormats
        }

        // Supported exposure stops (authoritative device lists)
        await refreshSupportedExposure()

        // Dynamic range
        if let dr = try? await c.get(Endpoint.dynamicRange, as: DynamicRangeValue.self) { dynamicRange = dr.dynamicRange }
        if let sdr = try? await c.get(Endpoint.supportedDynamicRanges, as: SupportedDynamicRanges.self) {
            supportedDynamicRanges = sdr.supportedDynamicRanges
        }

        // Recording tools + monitoring
        if let pr = try? await c.get(Endpoint.proxyRecording, as: EnabledValue.self) { proxyRecording = pr.enabled }
        if let disp = try? await c.get(Endpoint.monitoringDisplay, as: MonitoringDisplays.self), let first = disp.displays.first {
            monitorDisplay = first
        }
        if let fc = try? await c.get(Endpoint.falseColor(monitorDisplay), as: EnabledValue.self) { falseColor = fc.enabled }
        if let fa = try? await c.get(Endpoint.focusAssistDisplay(monitorDisplay), as: EnabledValue.self) { focusAssist = fa.enabled }
        if let fgOn = try? await c.get(Endpoint.frameGuideDisplay(monitorDisplay), as: EnabledValue.self) { frameGuide = fgOn.enabled }
        if let zb = try? await c.get(Endpoint.zebra, as: ZebraValue.self) { zebraRaw = zb; zebra = zb.highlight?.enabled ?? false }
        if let fg = try? await c.get(Endpoint.frameGuideRatio, as: FrameGuideRatioValue.self) { frameGuideRatio = fg.ratio }
        if let fgp = try? await c.get(Endpoint.frameGuidePresets, as: FrameGuidePresets.self) { frameGuidePresets = fgp.presets }

        // Color correction
        if let v = try? await c.get(Endpoint.ccLift, as: ColorRGBL.self) { ccLift = v }
        if let v = try? await c.get(Endpoint.ccGamma, as: ColorRGBL.self) { ccGamma = v }
        if let v = try? await c.get(Endpoint.ccGain, as: ColorRGBL.self) { ccGain = v }
        if let v = try? await c.get(Endpoint.ccOffset, as: ColorRGBL.self) { ccOffset = v }
        if let v = try? await c.get(Endpoint.ccContrast, as: ContrastValue.self) { ccContrast = v }
        if let v = try? await c.get(Endpoint.ccColor, as: ColorValue.self) { ccColor = v }
        if let v = try? await c.get(Endpoint.ccLumaContribution, as: LumaContributionValue.self) { ccLumaContribution = v.lumaContribution }

        // Audio
        if let si = try? await c.get(Endpoint.audioSupportedInputs(0), as: [SupportedAudioInput].self) {
            audioSupportedInputs = si.filter(\.available).map(\.input)
        }
        for ch in 0..<2 {
            if let inp = try? await c.get(Endpoint.audioInput(ch), as: AudioInputValue.self) { audioInputs[ch] = inp.input }
            if let lvl = try? await c.get(Endpoint.audioLevel(ch), as: AudioLevelValue.self) {
                audioLevels[ch] = lvl.normalised ?? lvl.normalized ?? lvl.gain ?? 1
            }
            if let ph = try? await c.get(Endpoint.audioPhantom(ch), as: AudioPhantomValue.self) { audioPhantom[ch] = ph.enabled }
        }

        // Media
        if let ws = try? await c.get(Endpoint.mediaWorkingset, as: MediaWorkingset.self),
           let disk = ws.workingset.first(where: { $0.activeDisk == true }) ?? ws.workingset.first {
            storageVolume = disk.volume ?? disk.deviceName ?? "—"
            remainingRecordTime = disk.remainingRecordTime ?? 0
            remainingSpace = disk.remainingSpace ?? 0
            clipCount = disk.clipCount ?? 0
        }

        await loadPresets()
        await refreshSlate()
        await refreshHorizon()
    }

    /// `/camera/motionSensor/euler` (radians) → roll/pitch degrees. The iPhone's
    /// natural landscape shooting position reads roll ≈ −90°, so we offset by +90
    /// to make that the level (0°) point; falls back to the normalized `/horizon`
    /// value (±40°) if Euler isn't exposed.
    func refreshHorizon() async {
        guard let c = client else { return }
        if let e = try? await c.get(Endpoint.motionSensorEuler, as: EulerAngles.self),
           let roll = e.roll {
            horizonAvailable = true
            horizonRoll = Self.normalizeAngle(roll * 180 / .pi + 90)
            horizonPitch = (e.pitch ?? 0) * 180 / .pi
        } else if let h = try? await c.get(Endpoint.motionSensorHorizon, as: HorizonValue.self),
                  let n = h.normalised {
            horizonAvailable = true
            horizonRoll = (n - 0.5) * 80        // 0…1 maps to ±40°
            horizonPitch = 0
        }
    }

    /// Wrap an angle in degrees to (−180, 180].
    private static func normalizeAngle(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d
    }

    /// `/slates/nextClip` — scene / take / reel. Take auto-increment is kept on.
    func refreshSlate() async {
        guard let c = client else { return }
        if let s = try? await c.get(Endpoint.slateNextClip, as: SlateData.self) {
            if let clip = s.clip {
                if let v = clip.scene { slateScene = v }
                if let v = clip.take { slateTake = v }
                if let v = clip.reel { slateReel = v }
            }
            if let l = s.lens {
                if let v = l.lensType { slateLensType = v }
                if let v = l.iris { slateIris = v }
                if let v = l.focalLength { slateFocalLength = v }
                if let v = l.distance { slateDistance = v }
                if let v = l.filter { slateFilter = v }
            }
            if let p = s.project {
                if let v = p.projectName { slateProjectName = v }
                if let v = p.director { slateDirector = v }
                if let v = p.camera { slateCamera = v }
                if let v = p.cameraOperator { slateCameraOperator = v }
            }
        }
        if let ai = try? await c.get(Endpoint.slateTakeAutoIncrement, as: TakeAutoIncrement.self), !ai.enabled {
            _ = try? await c.put(Endpoint.slateTakeAutoIncrement, TakeAutoIncrement(enabled: true))
        }
    }

    /// Pull the camera's supported ISO list and shutter-angle stops. Called on
    /// connect and whenever an exposure editor opens (the ISO list is lens-aware).
    func refreshSupportedExposure() async {
        guard let c = client else { return }
        if let iso = try? await c.get(Endpoint.supportedISOs, as: SupportedISOs.self) {
            supportedISOs = iso.supportedISOs
        }
        if let sh = try? await c.get(Endpoint.supportedShutters, as: SupportedShutters.self),
           let angles = sh.shutterAngles {
            supportedShutterAngles = angles.sorted()
        }
    }

    /// 2 Hz poll of fast-changing values (record, timecode, lens). Every ~1.5 s
    /// it also re-reads the "hot" exposure/lens values so the surface stays in
    /// sync with on-device changes even if the event socket isn't delivering.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self, let c = self.client else { return }
                if let rec = try? await c.get(Endpoint.record, as: RecordState.self) {
                    self.isRecording = rec.recording
                }
                if let z = try? await c.get(Endpoint.zoom, as: ZoomValue.self), let mm = z.focalLength {
                    self.focalLength = mm
                }
                if let tc = try? await c.get(Endpoint.timecode, as: TimecodeState.self) {
                    if let disp = tc.display ?? tc.timeline { self.timecode = disp }
                    else if let packed = tc.timecode { self.timecode = Timecode.string(fromBCD: packed) }
                }
                if self.horizonAvailable {
                    await self.refreshHorizon()
                }
                tick += 1
                if tick % 3 == 0 { await self.hotRefresh() }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Re-read the values a camera operator changes most often.
    private func hotRefresh() async {
        guard let c = client else { return }
        if let v = try? await c.get(Endpoint.iso, as: ISOValue.self) { iso = v.iso }
        if let v = try? await c.get(Endpoint.whiteBalance, as: WhiteBalanceValue.self) { whiteBalance = v.whiteBalance }
        if let v = try? await c.get(Endpoint.whiteBalanceTint, as: WhiteBalanceTintValue.self) { tint = v.whiteBalanceTint }
        if let s = try? await c.get(Endpoint.shutter, as: ShutterValue.self), let raw = s.shutterAngle {
            shutterAngle = ShutterAngle.degrees(from: raw)
        }
        if let f = try? await c.get(Endpoint.focus, as: FocusValue.self) { focusNormalised = f.normalised }
        if let i = try? await c.get(Endpoint.iris, as: IrisValue.self) {
            if let f = i.apertureStop { irisFStop = f } else if let n = i.apertureNumber { irisFStop = n / 100 }
        }
        if let ae = try? await c.get(Endpoint.autoExposure, as: AutoExposureValue.self), let m = ae.mode { aeMode = m }
        await refreshSlate()
    }

    // MARK: - Live event socket (WebSocket)

    /// Connects to `/control/api/v1/event/websocket` and subscribes to property
    /// changes. Best-effort: if the handshake or subscribe schema differs on this
    /// firmware, polling above still keeps the UI correct.
    private func startEventSocket() {
        guard let url = URL(string: "wss://\(host):\(port)/control/api/v1/event/websocket") else { return }
        let task = wsSession.webSocketTask(with: url)
        wsTask = task
        task.resume()
        subscribeEvents()
        receiveNext()
    }

    private func subscribeEvents() {
        let props = [
            Endpoint.iso, Endpoint.whiteBalance, Endpoint.whiteBalanceTint, Endpoint.shutter,
            Endpoint.autoExposure, Endpoint.iris, Endpoint.focus, Endpoint.zoom, Endpoint.record,
            Endpoint.codecFormat, Endpoint.videoFormat, Endpoint.mediaWorkingset
        ]
        let msg: [String: Any] = ["type": "request",
                                  "data": ["action": "subscribe", "properties": props]]
        if let data = try? JSONSerialization.data(withJSONObject: msg),
           let str = String(data: data, encoding: .utf8) {
            wsTask?.send(.string(str)) { _ in }
        }
    }

    private func receiveNext() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.liveConnected = true
                    if case .string(let text) = message { self.handleEvent(text) }
                    self.receiveNext()
                }
            case .failure:
                Task { @MainActor in self.liveConnected = false }
            }
        }
    }

    /// Parse a `propertyValueChanged` event and route the value to state.
    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let property = d["property"] as? String,
              let value = d["value"],
              let valueData = try? JSONSerialization.data(withJSONObject: value) else { return }

        func dec<T: Decodable>(_ t: T.Type) -> T? { try? JSONDecoder().decode(t, from: valueData) }

        switch property {
        case Endpoint.iso:              if let v = dec(ISOValue.self) { iso = v.iso }
        case Endpoint.whiteBalance:     if let v = dec(WhiteBalanceValue.self) { whiteBalance = v.whiteBalance }
        case Endpoint.whiteBalanceTint: if let v = dec(WhiteBalanceTintValue.self) { tint = v.whiteBalanceTint }
        case Endpoint.shutter:          if let v = dec(ShutterValue.self), let raw = v.shutterAngle { shutterAngle = ShutterAngle.degrees(from: raw) }
        case Endpoint.autoExposure:     if let v = dec(AutoExposureValue.self), let m = v.mode { aeMode = m }
        case Endpoint.iris:             if let v = dec(IrisValue.self) { if let f = v.apertureStop { irisFStop = f } else if let n = v.apertureNumber { irisFStop = n / 100 } }
        case Endpoint.focus:            if let v = dec(FocusValue.self) { focusNormalised = v.normalised }
        case Endpoint.zoom:             if let v = dec(ZoomValue.self), let mm = v.focalLength { focalLength = mm }
        case Endpoint.record:           if let v = dec(RecordState.self) { isRecording = v.recording }
        case Endpoint.codecFormat:      if let v = dec(CodecFormatValue.self) { codec = v.codec }
        case Endpoint.videoFormat:      if let v = dec(SystemInfo.VideoFormat.self), let n = v.name { videoFormatName = n }
        default: break
        }
    }

    private func loadPresets() async {
        guard let c = client else { return }
        if let list = try? await c.get(Endpoint.presets, as: PresetList.self) { presets = list.presets }
        if let active = try? await c.get(Endpoint.activePreset, as: ActivePreset.self) { activePreset = active.preset }
    }

    private func applySystem(_ info: SystemInfo) {
        if let c = info.codecFormat?.codec { codec = c }
        if let vf = info.videoFormat {
            if let w = vf.width, let h = vf.height { resolution = "\(w)×\(h)" }
            else if let n = vf.name { resolution = n }
            if let fr = vf.frameRate { frameRate = fr }
        }
    }

    // MARK: - Writes (optimistic: update UI now, PUT in background)

    private func push(_ op: @escaping (BMDClient) async throws -> Void) {
        guard let c = client else { return }
        Task {
            do { try await op(c) }
            catch { lastError = (error as? BMDError)?.errorDescription ?? error.localizedDescription }
        }
    }

    func setISO(_ v: Int)   { iso = v;  push { try await $0.put(Endpoint.iso, ISOValue(iso: v)) } }

    /// Lowest ISO/EI the current lens allows (max is 3200 for all lenses).
    /// 24 mm & 48 mm bottom out at 54; the wider/longer lenses reach 15.
    var isoMinimum: Int { (focalLength == 24 || focalLength == 48) ? 54 : 15 }
    func setGain(_ v: Int)  { gain = v; push { try await $0.put(Endpoint.gain, GainValue(gain: v)) } }
    func setWhiteBalance(_ v: Int) { whiteBalance = v; push { try await $0.put(Endpoint.whiteBalance, WhiteBalanceValue(whiteBalance: v)) } }
    func setTint(_ v: Int)  { tint = v; push { try await $0.put(Endpoint.whiteBalanceTint, WhiteBalanceTintValue(whiteBalanceTint: v)) } }

    func setShutterAngle(_ deg: Double) {
        shutterAngle = deg
        let raw = ShutterAngle.raw(fromDegrees: deg, scaled: shutterIsAngleScaled)
        push { try await $0.put(Endpoint.shutter, ShutterValue(shutterSpeed: nil, shutterAngle: raw)) }
    }

    func setIris(normalised n: Double) {
        irisNormalised = n
        push { try await $0.put(Endpoint.iris, IrisValue(normalised: n, apertureStop: nil, apertureNumber: nil, continuousApertureAutoExposure: nil)) }
    }

    func setFocus(normalised n: Double) {
        focusNormalised = n
        push { try await $0.put(Endpoint.focus, FocusValue(normalised: n)) }
    }

    func toggleRecord() {
        let target = !isRecording
        isRecording = target
        push { try await $0.put(Endpoint.record, RecordState(recording: target)) }
    }

    func stillCapture() { push { try await $0.post(Endpoint.doStillCapture) } }

    func autoWhiteBalance() { push { try await $0.put(Endpoint.autoWhiteBalance, [String: String]()); await self.refreshWB() } }
    /// One-shot autofocus. `doAutoFocus` has no completion event, so we light the
    /// AF indicator for ~1.2 s to signal the pass is running.
    func autoFocus() {
        afActive = true
        push { try await $0.put(Endpoint.doAutoFocus, [String: String]()) }
        Task { try? await Task.sleep(for: .seconds(1.2)); afActive = false }
    }

    // MARK: Dynamic range / recording tools / monitoring

    func setDynamicRange(_ v: String) {
        dynamicRange = v
        push { try await $0.put(Endpoint.dynamicRange, DynamicRangeValue(dynamicRange: v)) }
    }
    func setProxyRecording(_ on: Bool) {
        proxyRecording = on
        push { try await $0.put(Endpoint.proxyRecording, EnabledValue(enabled: on)) }
    }
    func setFalseColor(_ on: Bool) {
        falseColor = on
        push { try await $0.put(Endpoint.falseColor(self.monitorDisplay), EnabledValue(enabled: on)) }
    }
    func setFocusAssist(_ on: Bool) {
        focusAssist = on
        push { try await $0.put(Endpoint.focusAssistDisplay(self.monitorDisplay), EnabledValue(enabled: on)) }
    }
    func setFrameGuide(_ on: Bool) {
        frameGuide = on
        push { try await $0.put(Endpoint.frameGuideDisplay(self.monitorDisplay), EnabledValue(enabled: on)) }
    }
    func setZebra(_ on: Bool) {
        zebra = on
        zebraRaw.highlight?.enabled = on
        let body = zebraRaw
        push { try await $0.put(Endpoint.zebra, body) }
    }
    func setFrameGuideRatio(_ ratio: String) {
        frameGuideRatio = ratio
        push { try await $0.put(Endpoint.frameGuideRatio, FrameGuideRatioValue(ratio: ratio)) }
    }

    // MARK: Format

    func setCodec(_ codec: String) {
        codecFull = codec
        push { try await $0.put(Endpoint.codecFormat, CodecFormatValue(codec: codec, container: "mov")) }
    }
    func setVideoFormat(_ name: String) {
        videoFormatName = name
        push { try await $0.put(Endpoint.videoFormat, VideoFormatValue(name: name)) }
    }

    /// The video format name packs resolution + frame rate ("3840x2160p29.97").
    /// These split it so Resolution and FPS can be their own tiles.
    var currentResolution: String { videoFormatName.components(separatedBy: "p").first ?? "" }
    var currentFPS: String {
        let parts = videoFormatName.components(separatedBy: "p")
        return parts.count > 1 ? parts[1] : ""
    }
    var availableResolutions: [String] {
        var seen = Set<String>(); var out: [String] = []
        for f in supportedVideoFormats {
            let r = f.components(separatedBy: "p").first ?? ""
            if !r.isEmpty, !seen.contains(r) { seen.insert(r); out.append(r) }
        }
        return out
    }
    func availableFPS(for resolution: String) -> [String] {
        supportedVideoFormats
            .filter { $0.hasPrefix(resolution + "p") }
            .map { $0.components(separatedBy: "p").last ?? "" }
    }
    func setResolution(_ res: String) {
        let fpsList = availableFPS(for: res)
        let fps = fpsList.contains(currentFPS) ? currentFPS : (fpsList.first ?? currentFPS)
        setVideoFormat("\(res)p\(fps)")
    }
    func setFPS(_ fps: String) {
        setVideoFormat("\(currentResolution)p\(fps)")
    }

    // MARK: Auto exposure

    func setAutoExposure(_ mode: String) {
        aeMode = mode
        push { try await $0.put(Endpoint.autoExposure, AutoExposureValue(mode: mode, type: nil)) }
    }

    // MARK: Color correction

    func setLift(_ v: ColorRGBL)   { ccLift = v;   push { try await $0.put(Endpoint.ccLift, v) } }
    func setGamma(_ v: ColorRGBL)  { ccGamma = v;  push { try await $0.put(Endpoint.ccGamma, v) } }
    func setGain(_ v: ColorRGBL)   { ccGain = v;   push { try await $0.put(Endpoint.ccGain, v) } }
    func setOffset(_ v: ColorRGBL) { ccOffset = v; push { try await $0.put(Endpoint.ccOffset, v) } }
    func setContrast(_ v: ContrastValue) { ccContrast = v; push { try await $0.put(Endpoint.ccContrast, v) } }
    func setColor(_ v: ColorValue) { ccColor = v; push { try await $0.put(Endpoint.ccColor, v) } }
    func setLumaContribution(_ v: Double) {
        ccLumaContribution = v
        push { try await $0.put(Endpoint.ccLumaContribution, LumaContributionValue(lumaContribution: v)) }
    }

    // MARK: Audio

    func setAudioInput(_ ch: Int, _ input: String) {
        audioInputs[ch] = input
        push { try await $0.put(Endpoint.audioInput(ch), AudioInputValue(input: input)) }
    }
    func setAudioLevel(_ ch: Int, _ normalised: Double) {
        audioLevels[ch] = normalised
        push { try await $0.put(Endpoint.audioLevel(ch), AudioLevelValue(gain: nil, normalised: normalised, normalized: normalised)) }
    }
    func setPhantom(_ ch: Int, _ enabled: Bool) {
        audioPhantom[ch] = enabled
        push { try await $0.put(Endpoint.audioPhantom(ch), AudioPhantomValue(enabled: enabled)) }
    }

    // MARK: Slate

    /// Each setter PUTs a partial slate (only the changed field) to the next-clip
    /// slate; the API merges it. Optimistic like the other writes.
    func setSlateScene(_ v: String) {
        slateScene = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(clip: SlateClip(scene: v))) }
    }
    func setSlateTake(_ v: Int) {
        slateTake = max(1, v)
        let t = slateTake
        push { try await $0.put(Endpoint.slateNextClip, SlateData(clip: SlateClip(take: t))) }
    }
    func setSlateReel(_ v: Int) {
        slateReel = max(1, v)
        let r = slateReel
        push { try await $0.put(Endpoint.slateNextClip, SlateData(clip: SlateClip(reel: r))) }
    }

    // Project block (free text)
    func setSlateProjectName(_ v: String) {
        slateProjectName = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(project: SlateProject(projectName: v))) }
    }
    func setSlateDirector(_ v: String) {
        slateDirector = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(project: SlateProject(director: v))) }
    }
    func setSlateCamera(_ v: String) {
        slateCamera = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(project: SlateProject(camera: v))) }
    }
    func setSlateCameraOperator(_ v: String) {
        slateCameraOperator = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(project: SlateProject(cameraOperator: v))) }
    }

    // Lens block (text; iris/focalLength may be auto-populated by the camera)
    func setSlateLensType(_ v: String) {
        slateLensType = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(lens: SlateLens(lensType: v))) }
    }
    func setSlateIris(_ v: String) {
        slateIris = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(lens: SlateLens(iris: v))) }
    }
    func setSlateFocalLength(_ v: String) {
        slateFocalLength = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(lens: SlateLens(focalLength: v))) }
    }
    func setSlateDistance(_ v: String) {
        slateDistance = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(lens: SlateLens(distance: v))) }
    }
    func setSlateFilter(_ v: String) {
        slateFilter = v
        push { try await $0.put(Endpoint.slateNextClip, SlateData(lens: SlateLens(filter: v))) }
    }

    func applyPreset(_ name: String) {
        activePreset = name
        push { try await $0.put(Endpoint.activePreset, ActivePreset(preset: name)); await self.refreshAll() }
    }

    /// Save the current camera state as a preset (creates or overwrites). The
    /// camera stores presets with a `.cset` extension.
    func savePreset(_ rawName: String) {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !name.lowercased().hasSuffix(".cset") { name += ".cset" }
        let path = Endpoint.preset(name)
        push { try await $0.put(path); await self.loadPresets() }
    }

    func deletePreset(_ name: String) {
        if activePreset == name { activePreset = nil }
        let path = Endpoint.preset(name)
        push { try await $0.delete(path); await self.loadPresets() }
    }

    private func refreshWB() async {
        guard let c = client else { return }
        if let wb = try? await c.get(Endpoint.whiteBalance, as: WhiteBalanceValue.self) { whiteBalance = wb.whiteBalance }
        if let t = try? await c.get(Endpoint.whiteBalanceTint, as: WhiteBalanceTintValue.self) { tint = t.whiteBalanceTint }
    }
}
