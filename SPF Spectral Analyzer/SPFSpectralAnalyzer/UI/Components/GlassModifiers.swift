import SwiftUI

// MARK: - Liquid Glass View Modifiers

extension View {

    // MARK: Surface Effects

    /// Applies a regular Liquid Glass surface behind the view.
    func glassSurface(cornerRadius: CGFloat = 16, isInteractive: Bool = false) -> some View {
        let glass: Glass = isInteractive ? .regular.interactive() : .regular
        return self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    /// Applies a clear (highly translucent) Liquid Glass surface, ideal over visually rich backgrounds.
    func glassClearSurface(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        let base: Glass = .clear
        let glass = tint.map { base.tint($0) } ?? base
        return self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    // MARK: Button Styles

    /// Applies Liquid Glass button styling.
    @ViewBuilder
    func glassButtonStyle(isProminent: Bool = false) -> some View {
        if isProminent {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.glass)
        }
    }
}
