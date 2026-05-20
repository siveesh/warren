import SwiftUI

struct PerCoreUsageGrid: View {
    let usage: [Double]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
            ForEach(Array(usage.enumerated()), id: \.offset) { index, value in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Core \(index + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(Int((value * 100).rounded()))%")
                            .font(.caption2.weight(.bold))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))

                            Capsule()
                                .fill(AppPalette.accent)
                                .frame(width: max(10, proxy.size.width * value))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppPalette.secondaryCard.opacity(0.55))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
