import SwiftUI

struct AudioSetupAssistantView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("audioWizard.title"), systemImage: "wand.and.stars")
                .font(.title2.weight(.semibold))
            Group {
                switch step {
                case 0:
                    Text(L10n.text("audioWizard.devices"))
                    Text(L10n.text("audioWizard.devices.help")).foregroundStyle(.secondary)
                case 1:
                    Picker(L10n.text("settings.transmission"), selection: Binding(
                        get: { session.transmissionMode }, set: { session.setTransmissionMode($0) }
                    )) {
                        Text(L10n.text("audio.pushToTalk")).tag(AudioTransmissionMode.pushToTalk)
                        Text(L10n.text("settings.voiceActivity")).tag(AudioTransmissionMode.voiceActivity)
                        Text(L10n.text("settings.continuous")).tag(AudioTransmissionMode.continuous)
                    }
                default:
                    Text(L10n.text("audioWizard.test.help"))
                    Button(
                        session.audioLoopbackTestPhase == .idle ? L10n.text("settings.audioTest.start") : L10n.text("settings.audioTest.cancel"),
                        systemImage: "waveform.and.mic"
                    ) {
                        if session.audioLoopbackTestPhase == .idle { session.startAudioLoopbackTest() }
                        else { session.cancelAudioLoopbackTest() }
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            HStack {
                Button(L10n.text("common.cancel"), role: .cancel) { dismiss() }
                Spacer()
                Button(L10n.text("audioWizard.back")) { step -= 1 }.disabled(step == 0)
                Button(step == 2 ? L10n.text("audioWizard.finish") : L10n.text("audioWizard.next")) {
                    if step == 2 { dismiss() } else { step += 1 }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 560, height: 360)
    }
}
