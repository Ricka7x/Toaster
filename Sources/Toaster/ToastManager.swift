import Foundation

/// Lightweight, non-actionable feedback ("Saved", "Pinned", "Deleted") for a floating
/// toast pill. For anything that needs a button or explanation, use a real alert
/// instead. Supports a plain show-and-auto-dismiss path plus an optional loading flow
/// (`loading` → `completeLoading`/`failLoading`) for operations that take a moment.
///
/// Presentation (the actual view) is left to each host app, since it's normally tied to
/// that app's own design system and theming. This type only owns the state machine:
/// what toast is current, whether it's presented, and the show/dismiss/loading-transition
/// timing. Observe `current`/`isPresented` from a SwiftUI view to render it.
@MainActor
public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()

    /// The out-of-the-box value of `isEnabled` before a user has ever touched the
    /// setting. A host app that wants something other than `true` should set this once,
    /// before the first toast could possibly fire or a Settings screen could read
    /// `isEnabled` (e.g. the very top of `applicationDidFinishLaunching`). Matches
    /// `Logbook`'s DEBUG/release fallback in shape, except this default is a per-app
    /// product decision, not a build configuration, so it isn't baked in here.
    public static var defaultIsEnabled = true

    private static let isEnabledKey = "Toaster.isEnabled"

    @Published public private(set) var current: ToastData?
    /// Flips to `false` (still leaving `current` set) 0.3s before `current` itself is
    /// cleared, so a toast view has time to play an exit animation instead of the pill
    /// just vanishing the instant its duration expires.
    @Published public private(set) var isPresented = false

    /// User-configurable, default `Self.defaultIsEnabled`. `show` becomes a no-op while
    /// this is off, so callers don't need their own checks before calling
    /// `success`/`info`/`error`/`loading`.
    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.isEnabledKey) }
    }

    private let defaults: UserDefaults
    private var dismissTask: Task<Void, Never>?

    // MARK: - Loading-flow state

    /// How long a loading toast must stay visible once shown, so a fast operation
    /// doesn't produce an unreadable flash before it transitions to its result.
    private let minLoadingDisplayDuration: TimeInterval = 0.6
    private var loadingStartTime: Date?
    private var pendingCompletion: DispatchWorkItem?
    /// Only show the loading toast if the operation is still running after this delay.
    /// One that finishes sooner skips the loading phase entirely.
    private let loadingDebounceDelay: TimeInterval = 0.5
    private var loadingDebounceWork: DispatchWorkItem?

    /// Internal (not `private`) so tests can construct isolated instances via
    /// `@testable import` instead of sharing state through `.shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.isEnabledKey) as? Bool ?? Self.defaultIsEnabled
    }

    // MARK: - Simple show/dismiss

    public func show(
        _ message: String, style: ToastStyle = .info, duration: TimeInterval = 2.5, isWarning: Bool = false
    ) {
        guard isEnabled else { return }
        cancelPendingLoadingWork()
        dismissTask?.cancel()
        let toast = ToastData(message: message, style: style, duration: duration, isWarning: isWarning)
        current = toast
        isPresented = true
        guard duration > 0 else { return }
        dismissTask = Task { [weak self] in
            await Self.sleep(seconds: duration)
            guard !Task.isCancelled, let self, self.current?.id == toast.id else { return }
            self.isPresented = false

            await Self.sleep(seconds: 0.3)
            guard !Task.isCancelled, !self.isPresented else { return }
            self.current = nil
        }
    }

    public func success(_ message: String, duration: TimeInterval = 2.5) {
        show(message, style: .success, duration: duration)
    }

    public func info(_ message: String, duration: TimeInterval = 2.5) {
        show(message, style: .info, duration: duration)
    }

    public func error(_ message: String, duration: TimeInterval = 2.5) {
        show(message, style: .error, duration: duration)
    }

    /// Dismisses whatever toast is current, playing the same fade-out grace period as a
    /// natural duration expiry instead of vanishing instantly.
    public func dismiss() {
        guard current != nil else { return }
        isPresented = false
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            await Self.sleep(seconds: 0.3)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    // MARK: - Loading flow

    /// Registers a loading operation. The loading toast itself is deferred by a short
    /// debounce; if `completeLoading`/`failLoading` fires before that delay elapses, the
    /// loading phase is skipped entirely and only the result toast is shown.
    public func loading(message: String) {
        guard isEnabled else { return }
        pendingCompletion?.cancel()
        pendingCompletion = nil
        loadingDebounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.loadingDebounceWork = nil
            self.loadingStartTime = Date()
            self.show(message, style: .loading, duration: 0)
        }
        loadingDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingDebounceDelay, execute: work)
    }

    /// Updates an in-flight loading toast's message. No-op if loading hasn't appeared
    /// yet (still debouncing) or if the current toast isn't a loading toast.
    public func updateLoading(message: String) {
        guard let toast = current, toast.style == .loading else { return }
        current = ToastData(message: message, style: .loading, duration: 0)
    }

    /// Completes a loading operation with a success toast. If the loading toast hasn't
    /// appeared yet (debounce still pending), skips it and shows the result directly;
    /// otherwise waits out the minimum display time before transitioning.
    ///
    /// Pass `isWarning: true` when the operation finished but only partly well. The toast is
    /// still `.success` (see `ToastData.isWarning`); the host draws it as a warning.
    public func completeLoading(message: String, duration: TimeInterval = 3.0, isWarning: Bool = false) {
        transitionFromLoading(to: .success, message: message, duration: duration, isWarning: isWarning)
    }

    /// Completes a loading operation with an error toast. Same debounce-skip logic as
    /// `completeLoading`.
    public func failLoading(message: String, duration: TimeInterval = 3.0) {
        transitionFromLoading(to: .error, message: message, duration: duration)
    }

    /// Cancels all in-flight timers/work and clears the current toast. Meant for test
    /// teardown, restoring a clean slate between tests sharing `.shared`.
    public func cancelAllPendingWork() {
        dismissTask?.cancel()
        dismissTask = nil
        pendingCompletion?.cancel()
        pendingCompletion = nil
        loadingDebounceWork?.cancel()
        loadingDebounceWork = nil
        loadingStartTime = nil
        current = nil
        isPresented = false
    }

    private func transitionFromLoading(
        to style: ToastStyle, message: String, duration: TimeInterval, isWarning: Bool = false
    ) {
        if let work = loadingDebounceWork {
            work.cancel()
            loadingDebounceWork = nil
            show(message, style: style, duration: duration, isWarning: isWarning)
            return
        }
        guard current?.style == .loading else { return }
        pendingCompletion?.cancel()
        let elapsed = loadingStartTime.map { Date().timeIntervalSince($0) } ?? minLoadingDisplayDuration
        let delay = max(0, minLoadingDisplayDuration - elapsed)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.current?.style == .loading else { return }
            self.pendingCompletion = nil
            self.show(message, style: style, duration: duration, isWarning: isWarning)
        }
        pendingCompletion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingLoadingWork() {
        loadingDebounceWork?.cancel()
        loadingDebounceWork = nil
        pendingCompletion?.cancel()
        pendingCompletion = nil
    }

    /// `Task.sleep(for:)` needs macOS 13/iOS 16; this package's floor is macOS 12/iOS 15
    /// (matching a host app that hasn't raised its own deployment target), so timed waits
    /// go through the older nanoseconds-based API instead. Cancellation still throws
    /// `CancellationError`, which callers here always swallow with `try?`.
    private static func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    // MARK: - Legacy-settings migration

    /// One-time migration for a host app that persisted its own "show toast
    /// notifications" preference under its own key before adopting Toaster. No-op if
    /// Toaster's own key is already set (from a previous migration, or because the user
    /// has toggled `isEnabled` since adopting Toaster) or if nothing was ever persisted
    /// under `legacyKey`. Call once, early at launch, before anything could read
    /// `.shared.isEnabled` (e.g. a Settings screen).
    public static func migrateLegacyEnabledSetting(fromKey legacyKey: String, defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: isEnabledKey) == nil,
            let legacyValue = defaults.object(forKey: legacyKey) as? Bool
        else { return }
        defaults.set(legacyValue, forKey: isEnabledKey)
    }
}

// MARK: - Alternate naming

extension ToastManager {
    /// Alternate spelling of `success(_:duration:)`, matching a naming convention some
    /// call sites already use.
    public func showSuccess(message: String, duration: TimeInterval = 3.0) {
        success(message, duration: duration)
    }

    /// Alternate spelling of `error(_:duration:)`.
    public func showError(message: String, duration: TimeInterval = 3.0) {
        error(message, duration: duration)
    }

    /// Alternate spelling of `info(_:duration:)`.
    public func showInfo(message: String, duration: TimeInterval = 3.0) {
        info(message, duration: duration)
    }

    /// Alternate spelling of `loading(message:)`.
    public func showLoading(message: String) {
        loading(message: message)
    }
}
