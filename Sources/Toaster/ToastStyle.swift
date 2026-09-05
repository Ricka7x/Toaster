import Foundation

/// Visual category of a toast. Color and layout are left to the host app's own theme:
/// this only carries what's shared: which glyph goes with which category.
public enum ToastStyle: Equatable, Sendable {
    case success
    case info
    case error
    /// An in-progress operation with no fixed end time. Pairs with
    /// `ToastManager.loading(_:)`/`completeLoading(_:duration:)`/`failLoading(_:duration:)`.
    /// Has no glyph of its own (`systemImageName` is `nil`). Host views typically show a
    /// spinner here instead of a static icon.
    case loading

    /// SF Symbol name for this style, or `nil` for `.loading`.
    public var systemImageName: String? {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .loading: return nil
        }
    }
}
