package com.adriano.lumemusic.data

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/** Equivalente ao stripVideoTrack do iOS: tira a faixa de vídeo do MP4 baixado (sem recodificar). */
object AudioRemux {
    /**
     * Copia só a faixa de áudio de [file] para um .m4a temporário (MediaExtractor + MediaMuxer, cópia bruta das amostras)
     * e troca o original por ele. Se qualquer passo falhar, o original fica intacto. Devolve o arquivo final.
     */
    fun stripVideoTrack(file: File): File {
        val tmp = File(file.parentFile, file.nameWithoutExtension + ".strip.tmp")
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor = MediaExtractor().also { it.setDataSource(file.absolutePath) }
            var audioIdx = -1
            var hasVideo = false
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) hasVideo = true
                else if (mime.startsWith("audio/") && audioIdx < 0) audioIdx = i
            }
            if (!hasVideo || audioIdx < 0) { tmp.delete(); return file }

            extractor.selectTrack(audioIdx)
            val fmt = extractor.getTrackFormat(audioIdx)
            muxer = MediaMuxer(tmp.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outTrack = muxer.addTrack(fmt)
            muxer.start(); muxerStarted = true

            var cap = 256 * 1024
            if (fmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) cap = maxOf(cap, fmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
            val buf = ByteBuffer.allocate(cap)
            val info = MediaCodec.BufferInfo()
            while (true) {
                buf.clear()
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break
                info.set(0, size, extractor.sampleTime, extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC)
                muxer.writeSampleData(outTrack, buf, info)
                extractor.advance()
            }
            muxer.stop(); muxerStarted = false
            muxer.release(); muxer = null
            extractor.release(); extractor = null

            if (tmp.length() <= 32768) { tmp.delete(); return file }
            val dest = File(file.parentFile, file.nameWithoutExtension + ".m4a")
            if (dest == file && !file.delete()) { tmp.delete(); return file }
            if (!tmp.renameTo(dest)) { tmp.delete(); return file }
            if (dest != file) file.delete()
            return dest
        } catch (_: Throwable) {
            try { if (muxerStarted) muxer?.stop() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
            tmp.delete()
            return file
        } finally {
            try { extractor?.release() } catch (_: Throwable) {}
        }
    }
}
