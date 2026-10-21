import Foundation

/// One toast's content. A new instance is created on every `show`/transition call
/// (including `updateLoading`, which is a message change, not a mutation). `id` is what
/// lets `ToastManager` tell "still the same toast" from "a new one replaced it".
public struct ToastData: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let message: String
    public let style: ToastStyle
    public let duration: TimeInterval
    /// A result that resolved as `.success` but is only partly good ("Work partially restored").
    /// `style` stays `.success`, so a host's exhaustive `switch` over `ToastStyle` keeps
    /// compiling and a host that ignores this flag draws the same toast as before. A host that
    /// wants to tell them apart draws its own warning glyph and color when this is `true`.
    public let isWarning: Bool

    public init(message: String, style: ToastStyle, duration: TimeInterval, isWarning: Bool = false) {
        self.message = message
        self.style = style
        self.duration = duration
        self.isWarning = isWarning
    }
}
