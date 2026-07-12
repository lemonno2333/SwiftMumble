#include "COpusShim.h"

int nm_opus_configure_encoder(
    OpusEncoder *encoder,
    opus_int32 bitrate,
    int complexity,
    int packet_loss_percent,
    int inband_fec,
    int low_latency
) {
    int result = opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
    if (result != OPUS_OK) return result;
    result = opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(complexity));
    if (result != OPUS_OK) return result;
    result = opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(packet_loss_percent));
    if (result != OPUS_OK) return result;
    result = opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(inband_fec));
    if (result != OPUS_OK) return result;
    result = opus_encoder_ctl(
        encoder,
        OPUS_SET_APPLICATION(low_latency ? OPUS_APPLICATION_RESTRICTED_LOWDELAY : OPUS_APPLICATION_VOIP)
    );
    if (result != OPUS_OK) return result;
    return opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
}
