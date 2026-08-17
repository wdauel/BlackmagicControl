import Foundation

/// Codable models for the Blackmagic Camera Control REST API (`/control/api/v1`).
///
/// NOTE: The Blackmagic Camera app on iPhone serves this API on port 4444.
/// Shapes below follow Blackmagic's published Camera Control REST API. A couple
/// of fields (shutter-angle scaling, timecode encoding) vary by firmware — those
/// are flagged and converted in one place so they're trivial to correct once the
/// live probe JSON is captured.

// MARK: - Video

struct ISOValue: Codable { var iso: Int }
struct GainValue: Codable { var gain: Int }               // dB
struct WhiteBalanceValue: Codable { var whiteBalance: Int }        // Kelvin
struct WhiteBalanceTintValue: Codable { var whiteBalanceTint: Int }

/// `/video/shutter` — the iPhone app reports `shutterAngle` in plain degrees.
struct ShutterValue: Codable {
    var shutterSpeed: Int?          // 1/x (absent on iPhone)
    var shutterAngle: Double?       // degrees, e.g. 21.6
    var continuousShutterAutoExposure: Bool?
}

struct NDFilterValue: Codable {
    var stop: Double?               // ND stops (iPhone may omit — has no ND)
    var displayMode: String?        // "Stop" | "Number" | "Fraction"
}

/// `/video/autoExposure` — see the AutoExposureValue defined below.

// MARK: - Lens

struct IrisValue: Codable {
    var normalised: Double?         // 0…1
    var apertureStop: Double?       // f-number as a stop value
    var apertureNumber: Double?     // f-number
    var continuousApertureAutoExposure: Bool?
}

struct FocusValue: Codable {
    var normalised: Double          // 0 (near) … 1 (∞)
}

/// `GET/PUT /lens/focus/autoFocus` — AF enable + mode + live state.
struct AutoFocusValue: Codable {
    var enabled: Bool?
    var mode: String?               // "OneShot" | "Continuous"
    var state: String?              // Idle | Focusing | Focused | Paused | Error
    var supported: Bool?
}
/// `GET /lens/focus/autoFocus/description` — modes this device actually offers.
struct AutoFocusDescription: Codable {
    var supportedModes: [String]?   // e.g. ["OneShot","Continuous"]
    var supported: Bool?
}

struct ZoomValue: Codable {
    var normalised: Double?         // 0 (wide) … 1 (tele)
    var focalLength: Int?           // mm
}

// MARK: - Physical lens modules (camera selection)

/// One selectable physical camera module. Switching lens is `PUT /lens/cameras/active`
/// with `{"id": ...}`; the `id` string is authoritative (sending `index` alone → 500).
///
/// The display metadata (zoom factor, marketing focal length, name) is the fixed
/// iPhone 17 Pro hardware set from Blackmagic's docs — used both as the picker
/// list and as a fallback when the live `GET /lens/cameras` shape isn't decodable
/// on a given firmware. Selection/switching always route through the live `id`.
struct LensModule: Identifiable, Hashable {
    let id: String            // API id, e.g. "Lens24mm"
    let zoomFactor: String    // "1×"
    let focalLength: Int      // marketing mm (13, 24, 48, 100, 200)
    let name: String          // "Main"

    /// Verified rear modules on the iPhone 17 Pro / Pro Max (docs §"Lens Modules").
    static let iPhoneProRear: [LensModule] = [
        .init(id: "Lens13mm",        zoomFactor: "0.5×", focalLength: 13,  name: "Ultra Wide"),
        .init(id: "Lens24mm",        zoomFactor: "1×",   focalLength: 24,  name: "Main"),
        .init(id: "LensWASecondary", zoomFactor: "2×",   focalLength: 48,  name: "Main Fusion"),
        .init(id: "Lens77mm",        zoomFactor: "4×",   focalLength: 100, name: "Telephoto"),
        .init(id: "Lens200mm",       zoomFactor: "8×",   focalLength: 200, name: "Tele Fusion"),
    ]
}

/// `GET/PUT /lens/cameras/active` — the active module id.
struct ActiveLens: Codable { var id: String? }

/// `GET /lens/cameras` — best-effort decode of the enumerated module list; the
/// wrapper key varies by firmware, so both spellings are covered.
struct LensCameraDTO: Codable { var id: String?; var index: Int? }
struct LensCameras: Codable { var cameras: [LensCameraDTO]? }

/// `GET /lens/zoom/description` — zoom range of the *active* lens (shifts per module).
struct ZoomDescription: Codable {
    struct Range: Codable { var min: Double?; var max: Double? }
    var controllable: Bool?
    var focalLength: Range?
}

// MARK: - Transport

struct RecordState: Codable { var recording: Bool }

// MARK: - Pre-record (transport cache buffer)

struct PrerecordAuto: Codable { var autoEnabled: Bool }
struct PrerecordMaxDuration: Codable { var maxDuration: Int }   // seconds
/// `GET /transports/0/prerecord/supportedMaxDurations` — key spelling unverified
/// on this firmware, so cover the likely variants.
struct PrerecordSupportedDurations: Codable {
    var supportedMaxDurations: [Int]?
    var maxDurations: [Int]?
    var durations: [Int]?
    var values: [Int] { supportedMaxDurations ?? maxDurations ?? durations ?? [] }
}
/// `GET /transports/0/prerecord` — active state (shape unverified; cover likely keys).
struct PrerecordStatus: Codable {
    var prerecording: Bool?
    var enabled: Bool?
    var active: Bool?
    var value: Bool { prerecording ?? enabled ?? active ?? false }
}

// MARK: - Camera power / battery (`/camera/power`)

/// `/camera/power` (read-only). `source` ∈ Battery/AC/Fiber/USB/POE.
struct PowerStatus: Codable {
    struct Battery: Codable {
        var milliVolt: Int?
        var chargeRemainingPercent: Int?
        var statusFlags: [String]?
    }
    var source: String?
    var milliVolt: Int?
    var batteries: [Battery]?
}

/// `/transports/0/timecode`. The iPhone app returns preformatted strings
/// (`display` / `timeline`); some firmware returns a BCD-packed integer instead.
struct TimecodeState: Codable {
    var timecode: Int?              // BCD-packed 0xHHMMSSFF (hardware cameras)
    var display: String?           // "11:38:25:00"
    var timeline: String?          // "11:38:25:00"
}

// MARK: - Presets

struct PresetList: Codable { var presets: [String] }
struct ActivePreset: Codable { var preset: String? }

// MARK: - System (`/system`)

struct SystemInfo: Codable {
    struct VideoFormat: Codable {
        var name: String?          // "4032x3024p29.97"
        var width: Int?
        var height: Int?
        var frameRate: String?     // "29.97"
        var interlaced: Bool?
    }
    struct CodecFormat: Codable {
        var codec: String?         // "Apple ProRes RAW HQ"
        var container: String?     // "mov"
    }
    var videoFormat: VideoFormat?
    var codecFormat: CodecFormat?
    var deviceName: String?        // not always present
    var model: String?
}

// MARK: - Format (`/system/...`)

struct CodecFormatValue: Codable { var codec: String; var container: String? }
struct VideoFormatValue: Codable { var name: String }
struct SupportedCodecFormats: Codable { var codecFormats: [CodecFormatValue] }
struct SupportedVideoFormats: Codable { var videoFormats: [String] }

/// `/system/format` — composite current format; `codec` includes the quality
/// suffix ("Apple ProRes RAW HQ:High").
struct SystemFormat: Codable {
    var codec: String?
    var frameRate: String?
}

// MARK: - Auto exposure (`/video/autoExposure`)

struct AutoExposureValue: Codable {
    var mode: String?               // "Off" | "Continuous" | "OneShot"
    var type: String?               // "Shutter" | "Iris" | ...
}

// MARK: - Audio

struct AudioInputValue: Codable { var input: String }
struct AudioLevelValue: Codable {
    var gain: Double?
    var normalised: Double?
    var normalized: Double?         // firmware spells it both ways
}
struct AudioPhantomValue: Codable { var enabled: Bool }
struct SupportedAudioInput: Codable { var input: String; var available: Bool }

// MARK: - Color correction

/// lift / gamma / gain / offset all share this shape.
struct ColorRGBL: Codable {
    var red: Double; var green: Double; var blue: Double; var luma: Double
}
struct ContrastValue: Codable { var pivot: Double; var adjust: Double }
struct ColorValue: Codable { var hue: Double; var saturation: Double }
struct LumaContributionValue: Codable { var lumaContribution: Double }

// MARK: - Media

struct MediaWorkingset: Codable {
    struct Disk: Codable {
        var deviceName: String?
        var volume: String?
        var index: Int?
        var clipCount: Int?
        var totalSpace: Int64?
        var remainingSpace: Int64?
        var remainingRecordTime: Int?   // seconds (codec-aware estimate)
        var activeDisk: Bool?
    }
    var size: Int?
    var workingset: [Disk]
}

// MARK: - Transport

struct TransportState: Codable { var mode: String }   // InputPreview | InputRecord | Output | Playback

// MARK: - Supported value lists / deeper settings (API v2.1)

struct SupportedISOs: Codable { var supportedISOs: [Int] }
struct SupportedShutters: Codable { var shutterSpeeds: [Double]?; var shutterAngles: [Double]? }
struct ShutterMeasurement: Codable { var measurement: String }   // "ShutterAngle" | "ShutterSpeed"

struct DynamicRangeValue: Codable { var dynamicRange: String }
struct SupportedDynamicRanges: Codable { var supportedDynamicRanges: [String] }

struct EnabledValue: Codable { var enabled: Bool }   // falseColor, frameGuide, frameGrids, safeArea, displayLUT, OIS, cleanFeed

/// `/monitoring/{display}/brightness` — per-display screen brightness (0–100).
struct BrightnessValue: Codable { var brightness: Int }

struct MonitoringDisplays: Codable { var displays: [String] }
struct FocusAssistValue: Codable { var mode: String; var color: String?; var intensity: Int? }
struct ZebraBand: Codable { var type: String?; var level: Int?; var enabled: Bool }
struct ZebraValue: Codable { var skinTone: ZebraBand?; var highlight: ZebraBand? }
struct FrameGuideRatioValue: Codable { var ratio: String }
struct FrameGuidePresets: Codable { var presets: [String] }

/// `/monitoring/frameGrids` (global) — which grid overlays are on. At most 2;
/// if 2, one must be "Thirds". Verified values seen: "Crosshair".
struct FrameGridsValue: Codable { var frameGrids: [String] }
/// `/monitoring/safeAreaPercent` (global). Verified: `{ "percent": 93 }`.
struct SafeAreaPercentValue: Codable { var percent: Int }

/// `/system/product` — verified `{softwareVersion, productName, deviceName}`.
struct SystemProduct: Codable {
    var softwareVersion: String?
    var productName: String?   // "iPhone 17 Pro"
    var deviceName: String?    // "A"
}

// MARK: - Slate (`/slates/...`)

/// The `clip` block of a slate. Partial updates are supported by the API, and
/// Swift's `JSONEncoder` omits nil optionals — so a setter that fills only one
/// field PUTs only that field. Extra keys in a GET response are ignored.
struct SlateClip: Codable {
    var reel: Int?
    var scene: String?
    var take: Int?
    var shotType: String?          // "MS", "WS", "CU"…
    var takeType: String?          // "None" | "Pickup" | "Series"…
    var sceneLocation: String?     // "Interior" | "Exterior"
    var sceneTime: String?         // "Day" | "Night"…
    var goodTake: Bool?
}
/// Lens metadata block. On iPhone, iris/focalLength are typically auto-populated
/// from the active lens, so writes there may be overwritten by the camera.
struct SlateLens: Codable {
    var lensType: String?
    var iris: String?
    var focalLength: String?
    var distance: String?
    var filter: String?
}
/// Project metadata block — free text.
struct SlateProject: Codable {
    var projectName: String?
    var director: String?
    var camera: String?
    var cameraOperator: String?
}
struct SlateData: Codable { var clip: SlateClip?; var lens: SlateLens?; var project: SlateProject? }
struct TakeAutoIncrement: Codable { var enabled: Bool }

// MARK: - Camera motion sensor (`/camera/...`)

/// `/camera/motionSensor/euler` — orientation in radians (roll, pitch, yaw).
struct EulerAngles: Codable { var roll: Double?; var pitch: Double?; var yaw: Double? }

/// `/camera/motionSensor/horizon` — relative horizon, 0…1 (0.5 = level), ±40°.
/// Field name unverified; covers the likely spellings.
struct HorizonValue: Codable {
    var horizon: Double?
    var value: Double?
    var position: Double?
    var relative: Double?
    var normalised: Double? { horizon ?? value ?? position ?? relative }
}

// MARK: - Helpers

enum Timecode {
    /// Decode a BCD-packed 0xHHMMSSFF integer to "HH:MM:SS:FF".
    static func string(fromBCD packed: Int) -> String {
        func bcd(_ byte: Int) -> Int { ((byte >> 4) & 0xF) * 10 + (byte & 0xF) }
        let ff = bcd(packed & 0xFF)
        let ss = bcd((packed >> 8) & 0xFF)
        let mm = bcd((packed >> 16) & 0xFF)
        let hh = bcd((packed >> 24) & 0xFF)
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
}

enum ShutterAngle {
    /// Some firmware reports shutter angle in hundredths of a degree (18000 =
    /// 180.0°); others report plain degrees. Heuristic: values > 360 are scaled.
    static func degrees(from raw: Double) -> Double { raw > 360 ? raw / 100 : raw }
    static func raw(fromDegrees deg: Double, scaled: Bool) -> Double { scaled ? deg * 100 : deg }
}
