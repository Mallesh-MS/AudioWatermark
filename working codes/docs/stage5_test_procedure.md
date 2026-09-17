# Stage 5: Single-Phone Hardware-in-the-Loop Test

Stage 4's frequency table is assumed unchanged because no shifted-frequency result was supplied: preamble 17,000 Hz, bit 0 18,000 Hz, and bit 1 19,500 Hz. This stage uses the complete Stage 3 protocol with the phone's real speaker and microphone.

## Procedure

1. Install and launch the diagnostic build on one physical phone.
2. Tap **Start Listening** first and grant microphone permission.
3. Wait until the status says `listening`.
4. Tap **Send Test Message** a moment later.
5. Keep the phone still with its speaker close to its own microphone until playback and decoding finish.
6. Confirm that the decoded result is `STAGE5_SINGLE_PHONE_OK`.

The screen loads the host WAV, generates one AES key for the session, encrypts and embeds the test message, plays the mixed sample buffer at 44.1 kHz, and lets the receiver detect the preamble before decoding and decrypting the frame.

## Failure checks

### No detection at all

Check speaker volume, microphone permission, and whether the watermark amplitude of `0.02` needs tuning even at close range. Re-run the Stage 4 magnitude test at this exact speaker-to-microphone distance. Because the same-device path is closer than the two-phone Stage 4 setup, failure here is a stronger indication of a pipeline, sample-rate, or playback/recording issue than a hardware frequency limit.

### Partial or garbled detection

Check the timing between starting recording and starting transmission. Stage 5 introduces OS-level recording/playback asynchrony that the Stage 3 in-memory test did not have. Also check that the host WAV is long enough for the complete frame and that the phone is not clipping the mixed signal.

### Timeout behavior

After a preamble and valid header are detected, the receiver uses the protocol estimate `T = 1.1 + 0.8L` seconds, where `L` is the ciphertext length in bytes, before reporting `no message detected`. A manual stop also reports no result when no valid message has been recovered.

This cannot be verified in Codespaces. Run it on the target phone and report the status sequence and whether the exact test message is recovered. Do not change the frequency table based on one garbled result; first record the timing and raw hardware observations, then re-check Stage 4 or update the protocol deliberately.
