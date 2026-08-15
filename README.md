# Blackmagic Camera Control (macOS)

A native SwiftUI Mac app that controls the **Blackmagic Camera iPhone app** over its
Camera Control REST API (`http://<phone-ip>:4444/control/api/v1`). The UI emulates the
look of **bit.ctrl.app** and the **ARRI Companion** app: a dark control-surface grid of
tiles with big monospaced readouts, gradient Temp/Tint sliders, a circular shutter-angle
dial, and a hazard-ring REC button.

## Run

```
./run.command            # build release + launch
# or, for development:
swift run --disable-sandbox
```

> `--disable-sandbox` is required only because this repo lives inside a restricted
> environment; on a normal Mac plain `swift build` / `swift run` works.

On launch, enter the address shown in the Blackmagic Camera app (default
`10.11.1.186 : 4444`) and press **Connect**. The API is **HTTPS with a self-signed
cert**, which the app trusts automatically (`InsecureTrustDelegate`).

## Multiple cameras

The tab bar at the top holds one tab per phone. **+** adds a camera, right-click a tab to
**Remove** it, and each tab shows its own connection dot (and a red dot while recording).
Every camera keeps its own live connection, polling, and WebSocket, so they all stay
controllable at once — switching tabs just changes which one fills the dashboard. Rename a
camera by editing its name in the header. The camera list (name/host/port) persists across
launches and auto-reconnects. Managed by `CameraManager`; the selected `CameraController` is
injected into the per-camera screen.

## What's wired up (verified against firmware, 2026-08-14)

| Area          | Control                                             |
|---------------|-----------------------------------------------------|
| Exposure      | ISO/EI menu, Auto-Exposure mode (Off/Continuous/One-Shot) |
| White balance | Temp + Tint gradient sliders, kelvin presets, AWB   |
| Shutter       | 45/90/172.8/180° presets + fine-tune slider (degrees)|
| Iris          | ƒ readout (fixed lens — read-only)                  |
| Lens          | Focus (0.000–0.999) slider + AF; focal-length readout (read-only) |
| Format        | Codec picker + Video-Format picker (from supported lists) |
| Color         | Lift/Gamma/Gain/Offset RGBY, Contrast, Pivot, Hue, Saturation, Luma mix |
| Audio         | 2× channel: input picker, level slider, 48V phantom |
| Media         | Storage volume, remaining record time, clip count   |
| Transport     | REC toggle, live timecode + record state            |
| Presets       | List + recall active camera preset                  |
| **Live**      | WebSocket event push (`LIVE` pill) + 2 Hz / 1.5 s polling fallback |

**iPhone-specific notes:** `video/gain` and `video/ndFilter` return **404** (no such
hardware), so those are omitted. `lens/iris` reports a fixed aperture
(`apertureStop` / `apertureNumber`×100) with no `normalised`, so iris is read-only.
`lens/zoom` reports `focalLength` but **rejects all writes** (`400 {"success":false}`),
and there is no lens-selection route — the multi-lens switcher is an iOS-app-only feature
not exposed by the REST schema (shared with fixed-lens hardware cameras), so the Lens tile
is a live read-only readout. `transports/0/timecode` returns preformatted `display`/
`timeline` strings (no BCD).

**Unverified (needs a live check):** the WebSocket subscribe schema and the
color-correction slider ranges (Lift/Gamma ±2, Gain 0–4, etc.) are best-effort. Polling
keeps state correct regardless of the WebSocket; color ranges only affect slider feel, not
correctness. See the WebSocket note at the end.

Live values refresh on connect and poll continuously; edits are optimistic (UI updates
immediately, then PUTs to the camera).

## Architecture

```
Sources/BlackmagicControl/
  App.swift                  # @main, window + activation
  CameraController.swift     # @MainActor state, connect/poll/write actions
  Networking/
    BMDClient.swift          # async URLSession GET/PUT/POST + Endpoint paths
    Models.swift             # Codable payloads + BCD/shutter-angle helpers
  Design/
    Theme.swift              # colors, typography, panel styling
    Components.swift         # Tile, PanelCard, SegmentedControl, ReadoutTile…
    Widgets.swift            # GradientSlider, ShutterDial, RecButton, Timecode
  Views/
    RootView.swift           # top bar + connect screen
    Dashboard.swift          # the tile-grid dashboard
```

## Re-probing the API

Payload shapes are verified against the live device. If firmware changes or you point
this at BMD *hardware* (which does expose gain/ND/iris-normalised and may BCD-encode
timecode), re-probe from a Mac that can reach the camera and adjust the centralized
`Networking/Models.swift`:

```
for p in system video/iso video/whiteBalance video/whiteBalanceTint video/shutter \
         lens/iris lens/focus lens/zoom transports/0/record transports/0/timecode presets; do
  printf '\n=== %s ===\n' "$p"
  curl -k -s -w '  [%{http_code}]\n' "https://10.11.1.186:4444/control/api/v1/$p"
done
```

`ShutterAngle` (degrees vs. hundredths) and `Timecode` (string vs. BCD) auto-adapt.

## Building a shareable app

```
./Packaging/bundle.sh
```

Produces `build/BlackmagicControl.app` and `build/BlackmagicControl-<ver>.zip`.
The bundle is **ad-hoc signed** (no Apple Developer account needed) and includes the
app icon. Send the **.zip**.

Note: the build is **arm64-only (Apple Silicon)**. Intel Macs are not supported by
this bundle. To build a universal binary, add `-Xswiftc -target ...` for both arches
or archive from Xcode.

## Sharing / first launch (for recipients)

Because the app isn't notarized by Apple, Gatekeeper blocks the first open. Recipients
should do **one** of these once:

- **Right-click** the app → **Open** → **Open** in the dialog. (Only needed the first time.)
- Or in Terminal: `xattr -dr com.apple.quarantine /path/to/BlackmagicControl.app`

After that it opens normally like any app. Requires macOS 14 (Sonoma) or later, and the
Mac must be on the **same Wi-Fi/LAN** as the iPhone running the Blackmagic Camera app.
