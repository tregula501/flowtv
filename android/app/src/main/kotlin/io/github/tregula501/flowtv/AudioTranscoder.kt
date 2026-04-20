package io.github.tregula501.flowtv

import android.media.MediaCodec
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import java.nio.ByteBuffer

/**
 * Hardware-accelerated AC-3 → AAC transcoder using Android's MediaCodec API.
 *
 * Pipeline: AC-3 bytes → MediaCodec AC3 decoder → PCM → MediaCodec AAC encoder → ADTS AAC frames
 *
 * Fire tablets ship with OMX.dolby.ac3.decoder for hardware AC-3 decoding.
 */
class AudioTranscoder {
    companion object {
        private const val TAG = "AudioTranscoder"
        private const val SAMPLE_RATE = 44100
        private const val CHANNEL_COUNT = 2 // stereo output
        private const val AAC_BITRATE = 128000
        private const val TIMEOUT_US = 10000L // 10ms

        /** Check if AC-3 decoding is supported on this device. */
        fun isAc3Supported(): Boolean {
            val list = MediaCodecList(MediaCodecList.ALL_CODECS)
            val format = MediaFormat.createAudioFormat("audio/ac3", 48000, 6)
            return list.findDecoderForFormat(format) != null
        }
    }

    private var decoder: MediaCodec? = null
    private var encoder: MediaCodec? = null
    private var isStarted = false

    // Collect output AAC frames
    private val outputFrames = mutableListOf<ByteArray>()

    /**
     * Start the transcode pipeline. Call once before feeding data.
     * Returns false if AC-3 decoding is not supported.
     */
    fun start(): Boolean {
        try {
            // Find AC-3 decoder
            val decoderFormat = MediaFormat.createAudioFormat("audio/ac3", 48000, 6)
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            val decoderName = codecList.findDecoderForFormat(decoderFormat)
            if (decoderName == null) {
                Log.e(TAG, "No AC-3 decoder found on this device")
                return false
            }
            Log.i(TAG, "Using AC-3 decoder: $decoderName")

            decoder = MediaCodec.createByCodecName(decoderName)
            decoder!!.configure(decoderFormat, null, null, 0)
            decoder!!.start()

            // AAC encoder — configured after we get actual output format from decoder
            val encoderFormat = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                SAMPLE_RATE,
                CHANNEL_COUNT
            )
            encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, AAC_BITRATE)
            encoderFormat.setInteger(
                MediaFormat.KEY_AAC_PROFILE,
                android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC
            )
            encoderFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder!!.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder!!.start()

            isStarted = true
            Log.i(TAG, "Audio transcode pipeline started")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start audio transcode: ${e.message}")
            stop()
            return false
        }
    }

    /**
     * Feed AC-3 audio data and get back AAC ADTS frames.
     * Returns a list of complete ADTS frames, or empty if no output yet.
     */
    fun transcode(ac3Data: ByteArray): List<ByteArray> {
        if (!isStarted) return emptyList()
        outputFrames.clear()

        try {
            // Feed AC-3 in chunks, draining decoder→encoder after each feed.
            // MediaCodec input buffers are small (~4-16KB), so we must feed
            // incrementally and drain between feeds to avoid stalling.
            var offset = 0
            while (offset < ac3Data.size) {
                val chunkSize = feedDecoder(ac3Data, offset)
                if (chunkSize > 0) {
                    offset += chunkSize
                } else {
                    // No input buffer available — drain and retry
                    offset += 0
                }

                // Drain decoder → PCM → feed to encoder
                drainDecoderToEncoder()

                // Drain encoder → AAC ADTS frames
                drainEncoder()

                // If we couldn't feed and couldn't drain, break to avoid infinite loop
                if (chunkSize <= 0) {
                    drainDecoderToEncoder()
                    drainEncoder()
                    break
                }
            }

            // Final drain pass to flush remaining buffered data
            for (i in 0..5) {
                drainDecoderToEncoder()
                drainEncoder()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Transcode error: ${e.message}")
        }

        return outputFrames.toList()
    }

    /** Stop and release all codecs. */
    fun stop() {
        isStarted = false
        try {
            decoder?.stop()
            decoder?.release()
        } catch (_: Exception) {}
        try {
            encoder?.stop()
            encoder?.release()
        } catch (_: Exception) {}
        decoder = null
        encoder = null
        Log.i(TAG, "Audio transcode pipeline stopped")
    }

    /** Feed AC-3 data starting at [offset]. Returns number of bytes consumed, or 0 if no buffer available. */
    private fun feedDecoder(data: ByteArray, offset: Int): Int {
        val dec = decoder ?: return 0
        val inputIndex = dec.dequeueInputBuffer(TIMEOUT_US)
        if (inputIndex >= 0) {
            val inputBuffer = dec.getInputBuffer(inputIndex) ?: return 0
            inputBuffer.clear()
            val remaining = data.size - offset
            val size = minOf(remaining, inputBuffer.remaining())
            inputBuffer.put(data, offset, size)
            dec.queueInputBuffer(inputIndex, 0, size, 0, 0)
            return size
        }
        return 0
    }

    private fun drainDecoderToEncoder() {
        val dec = decoder ?: return
        val enc = encoder ?: return
        val bufferInfo = MediaCodec.BufferInfo()

        while (true) {
            val outputIndex = dec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            when {
                outputIndex >= 0 -> {
                    val pcmBuffer = dec.getOutputBuffer(outputIndex) ?: break
                    val pcmData = ByteArray(bufferInfo.size)
                    pcmBuffer.position(bufferInfo.offset)
                    pcmBuffer.get(pcmData, 0, bufferInfo.size)
                    dec.releaseOutputBuffer(outputIndex, false)

                    // Feed PCM to encoder
                    if (pcmData.isNotEmpty()) {
                        feedEncoder(pcmData, bufferInfo.presentationTimeUs)
                    }
                }
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val newFormat = dec.outputFormat
                    Log.i(TAG, "Decoder output format: $newFormat")
                }
                else -> break // INFO_TRY_AGAIN_LATER or other
            }
        }
    }

    private fun feedEncoder(pcmData: ByteArray, presentationTimeUs: Long) {
        val enc = encoder ?: return
        val inputIndex = enc.dequeueInputBuffer(TIMEOUT_US)
        if (inputIndex >= 0) {
            val inputBuffer = enc.getInputBuffer(inputIndex) ?: return
            inputBuffer.clear()
            val size = minOf(pcmData.size, inputBuffer.remaining())
            inputBuffer.put(pcmData, 0, size)
            enc.queueInputBuffer(inputIndex, 0, size, presentationTimeUs, 0)
        }
    }

    private fun drainEncoder() {
        val enc = encoder ?: return
        val bufferInfo = MediaCodec.BufferInfo()

        while (true) {
            val outputIndex = enc.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            when {
                outputIndex >= 0 -> {
                    val aacBuffer = enc.getOutputBuffer(outputIndex) ?: break
                    if (bufferInfo.size > 0 && bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        // Wrap raw AAC in ADTS header
                        val aacData = ByteArray(bufferInfo.size)
                        aacBuffer.position(bufferInfo.offset)
                        aacBuffer.get(aacData, 0, bufferInfo.size)

                        val adtsFrame = addAdtsHeader(aacData)
                        outputFrames.add(adtsFrame)
                    }
                    enc.releaseOutputBuffer(outputIndex, false)
                }
                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    Log.i(TAG, "Encoder output format: ${enc.outputFormat}")
                }
                else -> break
            }
        }
    }

    /**
     * Add a 7-byte ADTS header to raw AAC data.
     * Profile: AAC-LC, Sample rate: 44100Hz, Channels: 2 (stereo)
     */
    private fun addAdtsHeader(aacData: ByteArray): ByteArray {
        val frameLength = 7 + aacData.size
        val adts = ByteArray(frameLength)

        // Syncword: 0xFFF
        adts[0] = 0xFF.toByte()
        adts[1] = 0xF1.toByte() // MPEG-4, Layer 0, no CRC

        // Profile (AAC-LC=1), SampleRate (44100=4), Channel (2)
        adts[2] = ((1 shl 6) or (4 shl 2) or (0 shl 1) or (0)).toByte() // 0x50
        adts[3] = ((2 shl 6) or (frameLength shr 11 and 0x03)).toByte()
        adts[4] = ((frameLength shr 3) and 0xFF).toByte()
        adts[5] = (((frameLength and 0x07) shl 5) or 0x1F).toByte()
        adts[6] = 0xFC.toByte() // buffer fullness VBR

        System.arraycopy(aacData, 0, adts, 7, aacData.size)
        return adts
    }
}
