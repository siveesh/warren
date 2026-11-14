// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// The About window: the maker's two marks, the app icon, version, credits and contact links.
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack(spacing: 32) {
                    logo("Logo1", inverted: false)
                    Divider().frame(height: 74).opacity(0.3)
                    // The portrait is black line art, so it is inverted in dark mode to stay visible.
                    logo("Logo2", inverted: colorScheme == .dark)
                }
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text("Warren")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Maintenance, cleanup, uninstall and system insight for your Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(versionLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 8) {
                    Text("© 2026 Siveesh Kodapully")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Link("www.siveesh.com", destination: URL(string: "https://www.siveesh.com")!)
                        Text("•").foregroundStyle(.tertiary)
                        Link("siveesh@learnwithsk.com", destination: URL(string: "mailto:siveesh@learnwithsk.com")!)
                    }
                    .font(.callout)
                    Text("Free software under the GNU GPL, version 3 or later. Includes code from Peel by Țugui Dragoș-Constantin.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(36)
        }
        .frame(width: 480, height: 500)
    }

    @ViewBuilder
    private func logo(_ name: String, inverted: Bool) -> some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
            let view = Image(nsImage: image).resizable().scaledToFit().frame(width: 100, height: 100)
            if inverted { view.colorInvert() } else { view }
        } else {
            Color.clear.frame(width: 100, height: 100)
        }
    }
}
