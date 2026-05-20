import SwiftUI

struct TopProcessList: View {
    let processes: [ProcessActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if processes.isEmpty {
                Text("Process insight fills in after the first few monitoring samples.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(process.name)
                                .font(.caption.weight(.semibold))
                            Text(process.command)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("PID \(process.pid)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f%% CPU", process.cpuPercent))
                                .font(.caption.weight(.semibold))
                            Text(ByteFormatting.format(process.memoryBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.55))
                    )
                }
            }
        }
    }
}
