import Foundation

/// One toast's content. A new instance is created on every `show`/transition call
/// (including `updateLoading`, which is a message change, not a mutation). `id` is what
/// lets `ToastManager` tell "still the same toast" from "a new one replaced it".
public struct ToastData: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let message: String
    public let style: ToastStyle
    public let duration: TimeInterval

    public init(message: String, style: ToastStyle, duration: TimeInterval) {
        self.message = message
        self.style = style
        self.duration = duration
    }
}
