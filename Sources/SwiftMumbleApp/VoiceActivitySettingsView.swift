import SwiftUI

struct VoiceActivitySettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.text("vad.title"), systemImage: "waveform")
                    .fontWeight(.medium)
                Spacer()
                Text(L10n.text("vad.currentLevel", Int(session.microphoneLevelDB.rounded())))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Label(
                    session.isVoiceActivityDetected
                        ? L10n.text("vad.detected")
                        : L10n.text("vad.waiting"),
                    systemImage: session.isVoiceActivityDetected
                        ? "checkmark.circle.fill"
                        : "circle.dotted"
                )
                .font(.caption)
                .foregroundStyle(session.isVoiceActivityDetected ? .green : .secondary)
            }

            VoiceLevelBar(
                levelDB: session.microphoneLevelDB,
                thresholdDB: session.voiceActivityThresholdDB,
                isDetected: session.isVoiceActivityDetected
            )
            .frame(height: 24)

            HStack {
                Text("-70")
                Slider(
                    value: Binding(
                        get: { session.voiceActivityThresholdDB },
                        set: { session.setVoiceActivityThresholdDB($0) }
                    ),
                    in: -70 ... -5,
                    step: 1
                )
                Text("-5 dBFS")
            }
            .font(.caption.monospacedDigit())

            HStack {
                Text(L10n.text("vad.threshold", Int(session.voiceActivityThresholdDB.rounded())))
                    .font(.caption.weight(.medium))
                Spacer()
                Text(L10n.text("vad.noiseFloor", Int(session.noiseFloorDB.rounded())))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(L10n.text("vad.autoCalibrate")) {
                    session.autoCalibrateVoiceThreshold()
                }
                .controlSize(.small)
                .help(L10n.text("vad.autoCalibrate.help"))
            }
            Text(L10n.text("vad.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct VoiceLevelBar: View {
    let levelDB: Double
    let thresholdDB: Double
    let isDetected: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let levelWidth = width * normalized(levelDB)
            let thresholdX = width * normalized(thresholdDB)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(isDetected ? Color.green : Color.accentColor)
                    .frame(width: max(2, levelWidth))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 18)
                    .offset(x: min(max(0, thresholdX - 1), max(0, width - 2)))
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.primary)
                    .offset(x: min(max(0, thresholdX - 5), max(0, width - 10)), y: -10)
            }
            .frame(height: 12)
            .offset(y: 10)
        }
        .accessibilityLabel(L10n.text("vad.meter"))
        .accessibilityValue(L10n.text("vad.currentLevel", Int(levelDB.rounded())))
    }

    private func normalized(_ decibels: Double) -> Double {
        min(1, max(0, (decibels + 70) / 65))
    }
}
