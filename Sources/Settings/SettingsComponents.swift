import AppKit
import SwiftUI

@MainActor
struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var binding: Bool

    init(title: String, subtitle: String? = nil, binding: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._binding = binding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5.4) {
            Toggle(isOn: $binding) {
                Text(title)
                    .font(.body)
            }
            .toggleStyle(.checkbox)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct SettingsSection<Content: View>: View {
    let title: String?
    let caption: String?
    let contentSpacing: CGFloat
    private let content: () -> Content

    init(
        title: String? = nil,
        caption: String? = nil,
        contentSpacing: CGFloat = 14,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.caption = caption
        self.contentSpacing = contentSpacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: contentSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .underline(hovering, color: .ccAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundColor(.ccAccent)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
