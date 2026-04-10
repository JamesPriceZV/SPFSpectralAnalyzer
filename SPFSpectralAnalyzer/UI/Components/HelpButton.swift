import SwiftUI

/// Reusable contextual help button that shows a popover with an explanation.
/// Renders as a small `questionmark.circle` icon matching the app's existing help pattern.
///
/// Usage:
/// ```
/// HStack {
///     Text("Critical λ")
///     HelpButton("Critical Wavelength", message: "The wavelength at which...")
/// }
/// ```
struct HelpButton: View {
    let title: String
    let message: LocalizedStringKey
    let width: CGFloat

    @State private var isPresented = false

    /// Creates a help button with a title and explanation.
    /// - Parameters:
    ///   - title: Bold heading shown at the top of the popover.
    ///   - message: Markdown-capable explanation text. Supports **bold**, line breaks, etc.
    ///   - width: Popover width (default 320).
    init(_ title: String, message: LocalizedStringKey, width: CGFloat = 320) {
        self.title = title
        self.message = message
        self.width = width
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Divider()
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: width)
        }
    }
}
