package com.adriano.lumemusic.audio

import android.content.Context
import android.graphics.Bitmap
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Size
import coil3.toBitmap
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.LockArtStyle
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.ui.stage.LockArtRender
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

/**
 * Arte composta para a tela de bloqueio / notificação de mídia (porta de App/LockScreenArtwork.swift).
 *
 * Desenhamos UMA imagem de 1024 px por faixa+estilo (Vinil: prato+disco+reflexo+selo com a capa+braço;
 * Fita K7: cassete com etiqueta escrita à mão, capinha e carretéis), fora da thread principal, com cache de 4.
 * O AudioPlayer publica a capa simples primeiro e troca os metadados (artworkData) quando esta ficar pronta.
 */
object LockScreenArtwork {
    private val cache = object : LinkedHashMap<String, ByteArray>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?) = size > 4
    }

    /** JPEG (qualidade 90) da arte composta, ou null para "Capa" (usa a capa simples). */
    suspend fun image(ctx: Context, track: Track, coverUrl: String, style: LockArtStyle): ByteArray? {
        if (style == LockArtStyle.COVER || style == LockArtStyle.AUTOMATIC || coverUrl.isEmpty()) return null
        val key = "${track.id}#${style.raw}#${LibraryStore.vinylEdition.raw}#${LibraryStore.cassetteStyle.raw}"
        synchronized(cache) { cache[key] }?.let { return it }
        val cover = loadCover(ctx, coverUrl) ?: return null
        val edition = LibraryStore.vinylEdition
        val tape = LibraryStore.cassetteStyle
        val bytes = withContext(Dispatchers.Default) {
            try {
                val bmp = when (style) {
                    LockArtStyle.VINYL -> LockArtRender.vinyl(cover, edition)
                    LockArtStyle.CASSETTE -> LockArtRender.cassette(cover, track.title, track.artist, tape)
                    else -> return@withContext null
                }
                val out = ByteArrayOutputStream(256 * 1024)
                bmp.compress(Bitmap.CompressFormat.JPEG, 90, out)
                bmp.recycle()
                out.toByteArray()
            } catch (_: Throwable) { null }
        } ?: return null
        synchronized(cache) { cache[key] = bytes }
        return bytes
    }

    private suspend fun loadCover(ctx: Context, url: String): Bitmap? = try {
        val req = ImageRequest.Builder(ctx).data(url).size(Size(800, 800)).allowHardware(false).build()
        val res = SingletonImageLoader.get(ctx).execute(req) as? SuccessResult
        res?.image?.toBitmap()?.let { if (it.config == Bitmap.Config.HARDWARE) it.copy(Bitmap.Config.ARGB_8888, false) else it }
    } catch (_: Throwable) { null }
}
