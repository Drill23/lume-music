package com.adriano.lumemusic.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.os.Bundle
import android.widget.RemoteViews
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Size
import coil3.toBitmap
import com.adriano.lumemusic.MainActivity
import com.adriano.lumemusic.R
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.LibraryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Widget 4x1: capa pequena, título, artista e anterior / tocar-pausar / próxima. */
class LumeWidget4x1 : LumeWidgetBase()

/** Widget 4x2: capa grande com os mesmos controles. */
class LumeWidget4x2 : LumeWidgetBase()

/** Recebe as atualizações do sistema e os toques nos botões (PendingIntent → AudioPlayer, o mesmo caminho do app). */
abstract class LumeWidgetBase : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) = LumeWidget.requestUpdate(context)
    override fun onEnabled(context: Context) = LumeWidget.requestUpdate(context)
    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) = LumeWidget.requestUpdate(context)

    override fun onReceive(context: Context, intent: Intent) {
        when (val a = intent.action) {
            LumeWidget.ACTION_PREV, LumeWidget.ACTION_TOGGLE, LumeWidget.ACTION_NEXT -> LumeWidget.command(context, a)
            else -> super.onReceive(context, intent)
        }
    }
}

object LumeWidget {
    const val ACTION_PREV = "com.adriano.lumemusic.widget.PREV"
    const val ACTION_TOGGLE = "com.adriano.lumemusic.widget.TOGGLE"
    const val ACTION_NEXT = "com.adriano.lumemusic.widget.NEXT"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    @Volatile private var coverUrl: String? = null
    @Volatile private var coverBmp: Bitmap? = null

    private val providers = listOf(LumeWidget4x1::class.java to R.layout.widget_4x1, LumeWidget4x2::class.java to R.layout.widget_4x2)

    private class State(val title: String, val artist: String, val playing: Boolean, val coverUrl: String)

    /** Música atual; sem nenhuma tocando nesta sessão, a última tocada. */
    private fun state(ctx: Context): State {
        val cur = AudioPlayer.currentTrack
        val t = cur ?: LibraryStore.recentTracks.firstOrNull()
            ?: return State(ctx.getString(R.string.widget_idle_title), ctx.getString(R.string.widget_idle_subtitle), false, "")
        val url = (if (cur != null) AudioPlayer.currentArtwork else "").ifEmpty { ArtworkStore.url(t) }
        return State(t.title, t.artist, cur != null && AudioPlayer.isPlaying, url)
    }

    private fun hasWidgets(ctx: Context): Boolean {
        val mgr = AppWidgetManager.getInstance(ctx)
        return providers.any { (cls, _) -> mgr.getAppWidgetIds(ComponentName(ctx, cls)).isNotEmpty() }
    }

    /** Atualiza todos os widgets: texto e botões na hora, a capa assim que carregar. */
    fun requestUpdate(context: Context) {
        val app = context.applicationContext
        job?.cancel()
        job = scope.launch {
            if (!hasWidgets(app)) return@launch
            val s = state(app)
            push(app, s, if (s.coverUrl == coverUrl) coverBmp else null)
            if (s.coverUrl.isNotEmpty() && s.coverUrl != coverUrl) {
                val bmp = loadCover(app, s.coverUrl) ?: return@launch
                coverUrl = s.coverUrl; coverBmp = bmp
                push(app, state(app).let { if (it.coverUrl == s.coverUrl) it else s }, bmp)
            }
        }
    }

    private fun push(ctx: Context, s: State, bmp: Bitmap?) {
        val mgr = AppWidgetManager.getInstance(ctx)
        for ((cls, layout) in providers) {
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, cls))
            if (ids.isEmpty()) continue
            try { mgr.updateAppWidget(ids, build(ctx, cls, layout, s, bmp)) } catch (_: Exception) {}
        }
    }

    private fun build(ctx: Context, cls: Class<*>, layout: Int, s: State, bmp: Bitmap?): RemoteViews = RemoteViews(ctx.packageName, layout).apply {
        setTextViewText(R.id.w_title, s.title)
        setTextViewText(R.id.w_artist, s.artist)
        if (bmp != null) setImageViewBitmap(R.id.w_cover, bmp) else setImageViewResource(R.id.w_cover, R.drawable.widget_cover_placeholder)
        setImageViewResource(R.id.w_play, if (s.playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play)
        setOnClickPendingIntent(R.id.w_prev, broadcast(ctx, cls, ACTION_PREV))
        setOnClickPendingIntent(R.id.w_play, broadcast(ctx, cls, ACTION_TOGGLE))
        setOnClickPendingIntent(R.id.w_next, broadcast(ctx, cls, ACTION_NEXT))
        setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        ))
    }

    private fun broadcast(ctx: Context, cls: Class<*>, action: String): PendingIntent = PendingIntent.getBroadcast(
        ctx, action.hashCode() xor cls.name.hashCode(), Intent(ctx, cls).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** Toque num botão (thread principal do receiver). Sem nada na fila ainda, "tocar" começa pela última música tocada. */
    fun command(ctx: Context, action: String) {
        try {
            val idle = AudioPlayer.currentTrack == null
            if (idle || action == ACTION_TOGGLE) {
                if (idle) {
                    val recent = LibraryStore.recentTracks
                    if (recent.isNotEmpty()) AudioPlayer.play(recent.first(), recent, "Recentes")
                } else AudioPlayer.togglePlayPause()
            } else if (action == ACTION_PREV) AudioPlayer.previousTrack()
            else AudioPlayer.nextTrack()
        } catch (_: Exception) {}
        requestUpdate(ctx)
    }

    /** Capa reduzida (256 px), quadrada e com cantos arredondados, leve para o RemoteViews. */
    private suspend fun loadCover(ctx: Context, url: String): Bitmap? = try {
        val req = ImageRequest.Builder(ctx).data(url).size(Size(320, 320)).allowHardware(false).build()
        val res = SingletonImageLoader.get(ctx).execute(req) as? SuccessResult
        res?.image?.toBitmap()?.let { rounded(it, 256) }
    } catch (_: Throwable) { null }

    private fun rounded(src: Bitmap, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val side = minOf(src.width, src.height)
        val from = android.graphics.Rect((src.width - side) / 2, (src.height - side) / 2, (src.width + side) / 2, (src.height + side) / 2)
        val to = RectF(0f, 0f, size.toFloat(), size.toFloat())
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = size * 0.17f
        c.drawRoundRect(to, r, r, p)
        p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        c.drawBitmap(src, from, to, p.apply { isFilterBitmap = true })
        return out
    }
}
