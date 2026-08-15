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

struct ZoomValue: Codable {
    var normalised: Double?         // 0 (wide) … 1 (tele)
    var focalLength: Int?           // mm
}

// MARK: - Transport

struct RecordState: Codable { var recording: Bool }

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
        var remainingRecordTime: Int?   // minutes
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

struct EnabledValue: Codable { var enabled: Bool }   // falseColor, frameGuide, displayLUT, proxyRecording

struct MonitoringDisplays: Codable { var displays: [String] }
struct FocusAssistValue: Codable { var mode: String; var color: String?; var intensity: Int? }
struct ZebraBand: Codable { var type: String?; var level: Int?; var enabled: Bool }
struct ZebraValue: Codable { var skinTone: ZebraBand?; var highlight: ZebraBand? }
struct FrameGuideRatioValue: Codable { var ratio: String }
struct FrameGuidePresets: Codable { var presets: [String] }

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
