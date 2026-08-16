import Foundation

/// Endpoint paths, relative to `/control/api/v1`. Centralized so the entire API
/// surface can be audited/adjusted in one place.
enum Endpoint {
    static let system            = "/system"
    static let systemProduct     = "/system/product"
    static let codecFormat       = "/system/codecFormat"
    static let videoFormat       = "/system/videoFormat"
    static let supportedCodecs   = "/system/supportedCodecFormats"
    static let supportedVideos   = "/system/supportedVideoFormats"

    static let iso               = "/video/iso"
    static let supportedISOs     = "/video/supportedISOs"
    static let gain              = "/video/gain"
    static let whiteBalance      = "/video/whiteBalance"
    static let whiteBalanceTint  = "/video/whiteBalanceTint"
    static let autoWhiteBalance  = "/video/whiteBalance/doAuto"
    static let shutter           = "/video/shutter"
    static let shutterMeasurement = "/video/shutter/measurement"
    static let supportedShutters = "/video/supportedShutters"
    static let ndFilter          = "/video/ndFilter"
    static let autoExposure      = "/video/autoExposure"

    static let dynamicRange          = "/system/dynamicRange"
    static let supportedDynamicRanges = "/system/supportedDynamicRanges"

    // Monitoring / tools
    static let monitoringDisplay = "/monitoring/display"
    static let focusAssist       = "/monitoring/focusAssist"
    static let zebra             = "/monitoring/zebra"
    static let frameGuideRatio   = "/monitoring/frameGuideRatio"
    static let frameGuidePresets = "/monitoring/frameGuideRatio/presets"
    static func falseColor(_ display: String) -> String { "/monitoring/\(display)/falseColor" }
    static func focusAssistDisplay(_ display: String) -> String { "/monitoring/\(display)/focusAssist" }
    static func frameGuideDisplay(_ display: String) -> String { "/monitoring/\(display)/frameGuide" }
    static func frameGridsDisplay(_ display: String) -> String { "/monitoring/\(display)/frameGrids" }
    static func safeAreaDisplay(_ display: String) -> String { "/monitoring/\(display)/safeArea" }
    static func displayLUT(_ display: String) -> String { "/monitoring/\(display)/displayLUT" }
    static let frameGridsGlobal  = "/monitoring/frameGrids"
    static let safeAreaPercent   = "/monitoring/safeAreaPercent"

    static let iris              = "/lens/iris"
    static let focus             = "/lens/focus"
    static let doAutoFocus       = "/lens/focus/doAutoFocus"
    static let ois               = "/lens/opticalImageStabilization"
    static let zoom              = "/lens/zoom"

    static let record            = "/transports/0/record"
    static let timecode          = "/transports/0/timecode"
    static let doStillCapture    = "/transports/0/doStillCapture"

    static let mediaWorkingset   = "/media/workingset"
    static let mediaActive       = "/media/active"

    static let presets           = "/presets"
    static let activePreset      = "/presets/active"
    /// A single preset by name; the name is percent-encoded for the path.
    static func preset(_ name: String) -> String {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "/presets/\(enc)"
    }

    // Color correction
    static let ccLift            = "/colorCorrection/lift"
    static let ccGamma           = "/colorCorrection/gamma"
    static let ccGain            = "/colorCorrection/gain"
    static let ccOffset          = "/colorCorrection/offset"
    static let ccContrast        = "/colorCorrection/contrast"
    static let ccColor           = "/colorCorrection/color"
    static let ccLumaContribution = "/colorCorrection/lumaContribution"

    // Slate
    static let slateNextClip         = "/slates/nextClip"
    static let slateLastClip         = "/slates/lastClip"
    static let slateTakeAutoIncrement = "/slates/takeAutoIncrement"

    // Camera body / motion sensor
    static let motionSensorEuler     = "/camera/motionSensor/euler"
    static let motionSensorHorizon   = "/camera/motionSensor/horizon"

    // Audio (per channel)
    static func audioInput(_ ch: Int) -> String { "/audio/channel/\(ch)/input" }
    static func audioLevel(_ ch: Int) -> String { "/audio/channel/\(ch)/level" }
    static func audioPhantom(_ ch: Int) -> String { "/audio/channel/\(ch)/phantomPower" }
    static func audioSupportedInputs(_ ch: Int) -> String { "/audio/channel/\(ch)/supportedInputs" }
}

/// Errors surfaced to the UI.
enum BMDError: LocalizedError {
    case badURL
    case http(Int)
    case notConnected
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .badURL:            return "Invalid camera address."
        case .http(let code):    return "Camera returned HTTP \(code)."
        case .notConnected:      return "Not connected to a camera."
        case .underlying(let m): return m
        }
    }
}

/// Trusts the Blackmagic Camera app's self-signed TLS certificate. The app
/// serves the REST API over HTTPS on port 4444 with a self-signed cert, so
/// standard validation would reject it. Scoped to this app's own LAN traffic.
final class InsecureTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = InsecureTrustDelegate()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Thin async wrapper over the camera's REST API. Value type + `URLSession`, so
/// it is `Sendable` and cheap to pass around.
struct BMDClient: Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int = 4444) {
        self.host = host
        self.port = port
    }

    private var base: String { "https://\(host):\(port)/control/api/v1" }

    private var session: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
    }

    // MARK: Verbs

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await send(path, method: "GET", body: Optional<Int>.none)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func put<B: Encodable>(_ path: String, _ body: B) async throws -> Data {
        try await send(path, method: "PUT", body: body)
    }

    /// Body-less PUT — e.g. `PUT /presets/{name}` saves current camera state.
    @discardableResult
    func put(_ path: String) async throws -> Data {
        try await send(path, method: "PUT", body: Optional<Int>.none)
    }

    @discardableResult
    func post(_ path: String) async throws -> Data {
        try await send(path, method: "POST", body: Optional<Int>.none)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Data {
        try await send(path, method: "DELETE", body: Optional<Int>.none)
    }

    /// Convenience: is anything answering at the expected API root?
    func ping() async throws -> SystemInfo {
        try await get(Endpoint.system, as: SystemInfo.self)
    }

    // MARK: Core

    private func send<B: Encodable>(_ path: String, method: String, body: B?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw BMDError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw BMDError.http(http.statusCode)
            }
            return data
        } catch let e as BMDError {
            throw e
        } catch {
            throw BMDError.underlying(error.localizedDescription)
        }
    }
}
