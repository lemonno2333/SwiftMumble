#ifndef C_OPUS_SHIM_H
#define C_OPUS_SHIM_H

#include <opus/opus.h>

int nm_opus_configure_encoder(
    OpusEncoder *encoder,
    opus_int32 bitrate,
    int complexity,
    int packet_loss_percent,
    int inband_fec,
    int low_latency
);

#endif
