import SwiftUI

/// The atomic grid cell used across both reference apps: a tiny caption at the
/// top and a big value beneath. Optionally tappable, with an accent outline.
struct Tile<Content: View>: View {
    let caption: String
    var accent: Color? = nil          // outline tint (bit.ctrl uses red)
    var locked: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(caption).controlLabelStyle().lineLimit(1)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 2)
            content
                .frame(maxWidth: .infinity)
            Spacer(minLength: 2)
        }
        .padding(.vertical, 12).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .strokeBorder(accent?.opacity(hovering ? 0.9 : 0.5) ?? Color.clear,
                              lineWidth: accent == nil ? 0 : 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .modifier(TapIfNeeded(action: action))
    }
}

/// Applies an onTapGesture only when an action exists (so read-only tiles stay inert).
private struct TapIfNeeded: ViewModifier {
    let action: (() -> Void)?
    func body(content: Content) -> some View {
        if let action {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// A compact value tile with a lock toggle (top-right) and a popover editor,
/// mirroring the reference apps' lockable Shutter / White-Balance tiles. When
/// locked the value dims and the editor won't open.
struct LockTile<Editor: View>: View {
    let caption: String
    let value: String
    var unit: String? = nil
    var subValue: String? = nil
    var accent: Color = Theme.textPrimary
    @Binding var locked: Bool
    @ViewBuilder var editor: Editor

    @State private var show = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Spacer(minLength: 2)
                Text(caption).controlLabelStyle().lineLimit(1)
                Spacer(minLength: 2)
                Button { locked.toggle() } label: {
                    Image(systemName: locked ? "lock.fill" : "lock.open")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(locked ? Theme.textSecondary : Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 2)
            Button { if !locked { show = true } } label: {
                VStack(spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.readout(26))
                            .foregroundStyle(locked ? Theme.textTertiary : Theme.textPrimary)
                        if let unit { Text(unit).font(.readout(18)).foregroundStyle(Theme.textSecondary) }
                        if !locked {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    if let subValue {
                        Text(subValue)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                editor.padding(16).frame(width: 340).background(Theme.panel)
            }
            Spacer(minLength: 2)
        }
        .padding(.vertical, 12).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .strokeBorder(locked ? Theme.textSecondary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

/// A grey tile whose value opens a popover list of options — used for ISO,
/// Auto-Exposure, Codec, Format, FPS. Uses the plain `Tile` chrome (not a macOS
/// `Menu`) so it matches the surrounding grid and always shows the current value.
struct PickerTile: View {
    let caption: String
    let value: String
    var unit: String? = nil
    var subValue: String? = nil
    var valueSize: CGFloat = 28
    let options: [String]
    var current: String? = nil
    let onSelect: (String) -> Void

    @State private var show = false

    var body: some View {
        Tile(caption: caption, action: { if !options.isEmpty { show = true } }) {
            VStack(spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value.isEmpty ? "—" : value)
                        .font(.readout(valueSize)).foregroundStyle(Theme.textPrimary)
                    if let unit {
                        Text(unit).font(.readout(valueSize * 0.7)).foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
                .lineLimit(1).minimumScaleFactor(0.55)
                if let subValue {
                    Text(subValue)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { opt in
                        Button { onSelect(opt); show = false } label: {
                            HStack {
                                Text(opt).font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if current == opt {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(current == opt ? Theme.inset : Color.clear)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 220, height: min(CGFloat(options.count) * 33 + 10, 340))
            .background(Theme.panel)
        }
    }
}

/// A titled panel container used for grouped sections (WB sliders, presets…).
/// Optionally collapsible — a chevron on the right toggles the content
/// (down = open, right = collapsed).
struct PanelCard<Content: View>: View {
    let title: String
    var accent: Color = Theme.accent
    var trailing: AnyView? = nil
    var collapsible: Bool = false
    @ViewBuilder var content: Content

    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(title).font(.panelTitle).foregroundStyle(Theme.textPrimary)
                    .tracking(0.5)
                Spacer()
                if let trailing { trailing }
                if collapsible {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
                    } label: {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if !collapsed { content }
        }
        .padding(Theme.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }
}

/// Small status chip (connection state, recording, etc.).
struct StatusPill: View {
    let text: String
    var color: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Theme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(filled ? color : Theme.inset,
                    in: Capsule())
        .overlay(Capsule().strokeBorder(filled ? .clear : Theme.stroke, lineWidth: 1))
    }
}

/// A large numeric readout with a unit and caption — ARRI-style.
struct ReadoutTile: View {
    let value: String
    var unit: String? = nil
    let label: String
    var accent: Color = Theme.textPrimary
    var size: CGFloat = 30

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value).font(.readout(size)).foregroundStyle(accent)
                if let unit {
                    Text(unit).font(.unit).foregroundStyle(Theme.textSecondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            if !label.isEmpty { Text(label).controlLabelStyle() }
        }
    }
}

/// Custom segmented control with a sliding accent pill.
struct SegmentedControl<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var accent: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let isOn = opt.value == selection
                Text(opt.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            if isOn {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.18)) { selection = opt.value }
                    }
            }
        }
        .padding(4)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    @Namespace private var ns
}
