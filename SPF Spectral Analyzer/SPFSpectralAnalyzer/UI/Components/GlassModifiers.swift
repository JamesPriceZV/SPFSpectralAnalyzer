import SwiftUI

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        if #available(macOS 15.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.platformBackground.opacity(0.85))
            )
        }
    }

    @ViewBuilder
    func glassButtonStyle(isProminent: Bool = false) -> some View {
        if #available(macOS 15.0, *) {
            if isProminent {
                self.buttonStyle(GlassProminentButtonStyle())
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
