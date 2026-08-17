# Blackmagic Camera Control (macOS)

A native SwiftUI Mac app that controls the **Blackmagic Camera iPhone app** over its
Camera Control REST API (`http://<phone-ip>:4444/control/api/v1`).

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
