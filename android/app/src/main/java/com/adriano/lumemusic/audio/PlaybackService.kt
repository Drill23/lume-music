package com.adriano.lumemusic.audio

import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.adriano.lumemusic.MainActivity
import com.adriano.lumemusic.R

/** Player exposto à sessão: previous/next controlam a fila do Lume (não a do ExoPlayer, que tem 1 item). */
class SessionPlayer(p: Player) : ForwardingPlayer(p) {
    private val extra = Player.Commands.Builder()
        .addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM).build()

    override fun getAvailableCommands(): Player.Commands = super.getAvailableCommands().buildUpon().addAll(extra).build()
    override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)
    override fun hasNextMediaItem() = true
    override fun hasPreviousMediaItem() = true
    override fun seekToNext() = AudioPlayer.nextTrack()
    override fun seekToNextMediaItem() = AudioPlayer.nextTrack()
    override fun seekToPrevious() = AudioPlayer.previousTrack()
    override fun seekToPreviousMediaItem() = AudioPlayer.previousTrack()
}

/** Notificação / tela de bloqueio com capa, título e controles (MediaSession). */
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        PlayerHolder.init(this)
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, SessionPlayer(PlayerHolder.player)).setSessionActivity(open).build()
        setMediaNotificationProvider(DefaultMediaNotificationProvider(this).also { it.setSmallIcon(R.drawable.ic_stat_lume) })
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = PlayerHolder.player
        if (!p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        session?.release()
        session = null
        super.onDestroy()
    }
}
