# Toaster

A small, dependency-free toast manager for macOS/iOS apps: a floating "Saved"/"Pinned"/
"Something went wrong" pill that shows itself and auto-dismisses, plus an optional
loading -> success/error flow for operations that take a moment. No view included:
presentation is left to each host app's own design system; this only owns the state
machine.

## Usage

```swift
import Toaster

ToastManager.shared.success("Saved")
ToastManager.shared.info("Switched workspace")
ToastManager.shared.error("Something went wrong")
```

## Partial results

`completeLoading(message:duration:isWarning:)` takes `isWarning: true` for an operation that
finished but only partly well ("Work partially restored"). The toast is still `.success`, so a
host's exhaustive `switch` over `ToastStyle` keeps compiling and a host that ignores the flag
draws what it always did. A host that wants a warning glyph and color reads
`toast.isWarning`:

```swift
ToastManager.shared.completeLoading(message: "Work partially restored", isWarning: true)
```

## Styling

No view ships with this package, on purpose: color, glyph weight, background material,
and animation are all specific to a host app's own design system, and hardcoding any of
that here would mean either a generic look that fits nobody, or an API surface that grows
a parameter for every app's preference. `ToastStyle` itself carries no color at all, only
`systemImageName` (`nil` for `.loading`, since that style shows a spinner instead of a
fixed glyph).

Build a small, self-contained view that observes `ToastManager.shared` and supplies your
own color mapping:

```swift
struct ToastView: View {
    @ObservedObject private var toastManager = ToastManager.shared

    var body: some View {
        if let toast = toastManager.current {
            HStack(spacing: 8) {
                Group {
                    if let systemImageName = toast.style.systemImageName {
                        Image(systemName: systemImageName)
                    } else {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.6)
                    }
                }
                .foregroundStyle(Self.tint(for: toast.style))

                Text(toast.message)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            // Drive your entrance/exit animation off `toastManager.isPresented`, not
            // `current` directly: it flips to `false` ~0.3s before `current` clears,
            // which is the window an exit animation plays in.
            .opacity(toastManager.isPresented ? 1 : 0)
        }
    }

    private static func tint(for style: ToastStyle) -> Color {
        switch style {
        case .success: return .green
        case .info: return .accentColor
        case .error: return .red
        case .loading: return .secondary
        }
    }
}
```

Host this view once, pinned to the top of whatever window/panel should show toasts (a
floating overlay window works well on macOS, so a toast can appear regardless of which
window currently has focus). It renders nothing on its own when `current` is `nil`, so
placement is cheap.

## Loading flow

For an operation that takes a moment, `loading`/`completeLoading`/`failLoading` show a
debounced, minimum-duration loading toast that transitions to a result:

```swift
ToastManager.shared.loading(message: "Restoring workspace…")
// ...
ToastManager.shared.completeLoading(message: "Workspace restored")
// or, on failure:
ToastManager.shared.failLoading(message: "Restore failed")
```

The loading toast itself is deferred by ~0.5s. An operation that finishes before that
skips the loading phase entirely and shows only the result. Once the loading toast has
appeared, it stays up at least ~0.6s before transitioning, so a fast operation doesn't
produce an unreadable flash. `updateLoading(message:)` changes an in-flight loading
toast's message without restarting its timing.

## Settings

```swift
ToastManager.shared.isEnabled = false   // user-configurable, default true
```

Persists in `UserDefaults.standard` under the `Toaster.isEnabled` key. Set
`ToastManager.defaultIsEnabled` once at launch (before anything could read `isEnabled`,
e.g. the top of `applicationDidFinishLaunching`) if a host app wants a default other than
`true`. This is a per-app product decision, not something the package can bake in.

A host app that persisted its own "show notifications" preference under its own key
before adopting Toaster can carry that value over instead of silently resetting it:

```swift
ToastManager.migrateLegacyEnabledSetting(fromKey: "myapp.settings.showToastNotifications")
```

No-op if Toaster's own key is already set or nothing was ever persisted under the legacy
key. Call once, at the same point as `defaultIsEnabled`.

## Adding to a project

```swift
.package(url: "https://github.com/Ricka7x/Toaster", from: "1.0.0")
```

Or, for local development against a sibling checkout instead of a published tag:

```swift
.package(path: "../Toaster")
```
