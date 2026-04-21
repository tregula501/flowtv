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
        private const val SAMPLE_RATE = 48000 // match AC-3 decoder output
        private const val CHANNEL_COUNT = 2 // stereo output
        private const val AAC_BITRATE = 128000
        private const val TIMEOUT_US = 10000L // 10ms — fewer loops is more efficient than many 1ms loops

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

            // Priority 1 = batch/offline mode: process at max throughput, no throttling
            decoderFormat.setInteger(MediaFormat.KEY_PRIORITY, 1)

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
            encoderFormat.setInteger(MediaFormat.KEY_PRIORITY, 1) // batch/offline mode

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
     * Two-pass approach:
     *   Pass 1: Decode ALL AC-3 → accumulate raw PCM in memory
     *   Pass 2: Feed PCM to encoder in exact-sized chunks → collect AAC
     * This avoids buffer pressure issues where decoder/encoder compete.
     */
    fun transcode(ac3Data: ByteArray): List<ByteArray> {
        if (!isStarted) return emptyList()
        outputFrames.clear()

        try {
            // === PASS 1: Decode all AC-3 to PCM ===
            val allPcm = java.io.ByteArrayOutputStream()
            val dec = decoder ?: return emptyList()
            val bufferInfo = MediaCodec.BufferInfo()

            // Feed all AC-3 data to decoder
            var offset = 0
            while (offset < ac3Data.size) {
                val inputIndex = dec.dequeueInputBuffer(TIMEOUT_US)
                if (inputIndex >= 0) {
                    val inputBuffer = dec.getInputBuffer(inputIndex) ?: break
                    inputBuffer.clear()
                    val remaining = ac3Data.size - offset
                    val size = minOf(remaining, inputBuffer.remaining())
                    inputBuffer.put(ac3Data, offset, size)
                    dec.queueInputBuffer(inputIndex, 0, size, 0, 0)
                    offset += size
                }

                // Drain decoded PCM
                while (true) {
                    val outIdx = dec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                    if (outIdx >= 0) {
                        val pcmBuf = dec.getOutputBuffer(outIdx) ?: break
                        val pcm = ByteArray(bufferInfo.size)
                        pcmBuf.position(bufferInfo.offset)
                        pcmBuf.get(pcm, 0, bufferInfo.size)
                        dec.releaseOutputBuffer(outIdx, false)
                        allPcm.write(pcm)
                    } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        Log.i(TAG, "Decoder output format: ${dec.outputFormat}")
                    } else {
                        break
                    }
                }
            }

            // Final decoder drain
            for (i in 0..20) {
                val outIdx = dec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                if (outIdx >= 0) {
                    val pcmBuf = dec.getOutputBuffer(outIdx) ?: break
                    val pcm = ByteArray(bufferInfo.size)
                    pcmBuf.position(bufferInfo.offset)
                    pcmBuf.get(pcm, 0, bufferInfo.size)
                    dec.releaseOutputBuffer(outIdx, false)
                    allPcm.write(pcm)
                } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    continue
                } else {
                    break
                }
            }

            val pcmData = allPcm.toByteArray()
            Log.i(TAG, "Decoded ${ac3Data.size} bytes AC-3 → ${pcmData.size} bytes PCM")

            // === PASS 2: Encode PCM to AAC in exact chunks ===
            val enc = encoder ?: return emptyList()
            val chunkSize = 1024 * CHANNEL_COUNT * 2 // 4096 bytes = one AAC frame's worth
            var pcmOffset = 0

            while (pcmOffset < pcmData.size) {
                // Feed one chunk to encoder
                val encInIdx = enc.dequeueInputBuffer(TIMEOUT_US)
                if (encInIdx >= 0) {
                    val encBuf = enc.getInputBuffer(encInIdx) ?: break
                    encBuf.clear()
                    val remaining = pcmData.size - pcmOffset
                    val size = minOf(chunkSize, remaining, encBuf.remaining())
                    encBuf.put(pcmData, pcmOffset, size)
                    enc.queueInputBuffer(encInIdx, 0, size, 0, 0)
                    pcmOffset += size
                }

                // Drain encoder output
                drainEncoder()
            }

            // Final encoder drain
            for (i in 0..30) {
                drainEncoder()
            }

            Log.i(TAG, "Encoded ${pcmData.size} bytes PCM → ${outputFrames.size} AAC frames")
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

        // Profile (AAC-LC=1), SampleRate (48000=3), Channel (2)
        adts[2] = ((1 shl 6) or (3 shl 2) or (0 shl 1) or (0)).toByte()
        adts[3] = ((2 shl 6) or (frameLength shr 11 and 0x03)).toByte()
        adts[4] = ((frameLength shr 3) and 0xFF).toByte()
        adts[5] = (((frameLength and 0x07) shl 5) or 0x1F).toByte()
        adts[6] = 0xFC.toByte() // buffer fullness VBR

        System.arraycopy(aacData, 0, adts, 7, aacData.size)
        return adts
    }
}
