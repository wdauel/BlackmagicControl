import SwiftUI

/// Owns every connected camera and which one is currently in focus. Each
/// `CameraController` runs its own connection, polling, and event socket, so
/// multiple phones stay live and independently controllable at once.
@MainActor
final class CameraManager: ObservableObject {
    @Published var cameras: [CameraController] = []
    @Published var selectedID: UUID?

    private let storeKey = "bmd.cameras"

    /// Default tag letters / colors handed to new cameras, by creation order.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private static let tagPalette: [UInt32] = [
        0xE5383B, 0x2E6FE0, 0x2FB84F, 0xFFB020, 0x39C7FF, 0xA855F7, 0xEC4899, 0xF4F4F5
    ]

    var selected: CameraController? { cameras.first { $0.id == selectedID } }

    init() {
        load()
        if cameras.isEmpty { addCamera(select: true) }
        selectedID = cameras.first?.id
        // Auto-connect restored cameras; failures just show as "NO LINK".
        for cam in cameras { cam.connect() }
    }

    // MARK: Mutations

    @discardableResult
    func addCamera(host: String = "10.11.1.", select: Bool = true) -> CameraController {
        let i = cameras.count
        let cam = CameraController(name: "Camera \(i + 1)", host: host,
                                   letter: Self.alphabet[i % Self.alphabet.count],
                                   tagColorHex: Self.tagPalette[i % Self.tagPalette.count])
        cameras.append(cam)
        if select { selectedID = cam.id }
        save()
        return cam
    }

    func remove(_ cam: CameraController) {
        cam.disconnect()
        cameras.removeAll { $0.id == cam.id }
        if selectedID == cam.id { selectedID = cameras.first?.id }
        save()
    }

    func select(_ cam: CameraController) { selectedID = cam.id }

    // MARK: Persistence

    private struct Saved: Codable {
        var id: UUID; var name: String; var host: String; var port: Int
        var letter: String?      // added later — optional for backward compatibility
        var colorHex: UInt32?
    }

    func save() {
        let arr = cameras.map { Saved(id: $0.id, name: $0.name, host: $0.host, port: $0.port,
                                      letter: $0.letter, colorHex: $0.tagColorHex) }
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let arr = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        cameras = arr.enumerated().map { i, s in
            CameraController(id: s.id, name: s.name, host: s.host, port: s.port,
                             letter: s.letter ?? Self.alphabet[i % Self.alphabet.count],
                             tagColorHex: s.colorHex ?? Self.tagPalette[i % Self.tagPalette.count])
        }
    }
}
