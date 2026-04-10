import SwiftUI

// MARK: - Enterprise Grounding Badge

/// Small indicator showing Microsoft 365 enterprise grounding status.
/// Displays in the analysis panel header next to the AI provider badge.
struct EnterpriseGroundingBadge: View {
    let isSignedIn: Bool
    let isGrounded: Bool
    let citationCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if isGrounded && citationCount > 0 {
                Text("\(citationCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var iconName: String {
        if !isSignedIn {
            return "building.2"
        } else if isGrounded {
            return "building.2.fill"
        } else {
            return "building.2"
        }
    }

    private var iconColor: Color {
        if !isSignedIn {
            return .secondary
        } else if isGrounded {
            return .blue
        } else {
            return .green
        }
    }

    private var statusText: String {
        if !isSignedIn {
            return "M365"
        } else if isGrounded {
            return "Enterprise"
        } else {
            return "M365 Ready"
        }
    }
}
