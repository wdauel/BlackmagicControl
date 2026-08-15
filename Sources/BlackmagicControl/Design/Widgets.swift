import SwiftUI

// MARK: - Gradient slider (Temp / Tint)

/// A slider with a custom gradient track and a white puck, matching bit.ctrl's
/// Temp (amber→blue) and Tint (green→magenta) controls.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let gradient: Gradient
    var onCommit: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let x = min(max(frac * w, 9), w - 9)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .overlay(Circle().strokeBorder(.black.opacity(0.1), lineWidth: 1))
                    .offset(x: x - 9)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(g.location.x / w, 0), 1)
                        value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in onCommit?() }
            )
        }
        .frame(height: 22)
    }
}

extension Gradient {
    /// Amber → white → blue, like a color-temperature scale.
    static let temperature = Gradient(colors: [
        Color(hex: 0xFFB020), Color(hex: 0xF0E9D6), Color(hex: 0x4F86FF)
    ])
    /// Green → white → magenta, like a tint scale.
    static let tint = Gradient(colors: [
        Color(hex: 0x36D07A), Color(hex: 0xE8E8E8), Color(hex: 0xE24BC4)
    ])
}

// MARK: - REC button

/// The big central record button. Green when idle (ARRI STBY), red hazard ring
/// when recording.
struct RecButton: View {
    let isRecording: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Theme.record : Theme.accent)
                    .padding(10)
                    .shadow(color: (isRecording ? Theme.record : Theme.accent).opacity(0.5),
                            radius: pulse ? 14 : 6)
                Text(isRecording ? "REC" : "REC")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.black)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, rec in pulse = rec }
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
    }
}

// MARK: - Timecode display

/// Green monospaced timecode, like both apps' TC readout.
struct TimecodeView: View {
    let timecode: String        // "HH:MM:SS:FF"
    var running: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(running ? Theme.record : Theme.textTertiary)
                .frame(width: 8, height: 8)
            Text(timecode)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .tracking(1)
        }
    }
}

// MARK: - Horizon / level indicator

/// A compact artificial-horizon: a horizon line that rotates with roll and
/// slides with pitch, inside a circular bezel. Green when level, amber when off.
struct HorizonIndicator: View {
    let rollDegrees: Double
    let pitchDegrees: Double
    var diameter: CGFloat = 62

    private var level: Bool { abs(rollDegrees) < 1.5 && abs(pitchDegrees) < 1.5 }

    var body: some View {
        let color = level ? Theme.accent : Theme.amber
        let radius = diameter / 2
        // Map pitch (±40°) to a vertical offset, clamped inside the bezel.
        let pitchOffset = max(-radius, min(radius, CGFloat(pitchDegrees / 40) * radius))

        ZStack {
            Circle().fill(Theme.inset)
            Circle().strokeBorder(Theme.stroke, lineWidth: 1)

            // Rotating horizon line + short pitch ladder tick.
            ZStack {
                Rectangle().fill(color).frame(width: diameter * 0.72, height: 2)
                Rectangle().fill(color.opacity(0.5)).frame(width: diameter * 0.3, height: 1)
                    .offset(y: -8)
            }
            .offset(y: pitchOffset)
            .rotationEffect(.degrees(-rollDegrees))
            .clipShape(Circle())
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.15), value: rollDegrees)
        .animation(.easeOut(duration: 0.15), value: pitchDegrees)
    }
}

// MARK: - Transport bar

struct TransportControls: View {
    var onPrev: () -> Void = {}
    var onRewind: () -> Void = {}
    var onPlay: () -> Void = {}
    var onPause: () -> Void = {}
    var onForward: () -> Void = {}
    var onNext: () -> Void = {}
    var onStop: () -> Void = {}

    var body: some View {
        HStack(spacing: 22) {
            transportButton("backward.end.fill", onPrev)
            transportButton("backward.fill", onRewind)
            transportButton("play.fill", onPlay, tint: Theme.blue, big: true)
            transportButton("pause.fill", onPause)
            transportButton("forward.fill", onForward)
            transportButton("forward.end.fill", onNext)
        }
    }

    private func transportButton(_ symbol: String, _ action: @escaping () -> Void,
                                 tint: Color = Theme.textPrimary, big: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 24 : 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
