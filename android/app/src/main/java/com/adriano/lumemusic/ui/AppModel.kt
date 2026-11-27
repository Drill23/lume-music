package com.adriano.lumemusic.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.AppTab
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.DiscoverFeed
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MoodCategory
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.RemotePlaylist
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.DiscoveryService
import com.adriano.lumemusic.platform.Haptics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

sealed interface LumeRoute {
    data class Album(val album: AlbumShowcase) : LumeRoute
    data class Playlist(val id: String) : LumeRoute
    data class RemotePlaylistRoute(val playlist: RemotePlaylist) : LumeRoute
    data class Artist(val name: String, val deezerId: Long?) : LumeRoute
    data object ImportHub : LumeRoute
    data class Mood(val mood: MoodCategory) : LumeRoute
    data class Country(val country: ChartCountry) : LumeRoute
    data class Genre(val genre: MusicGenre) : LumeRoute
    data class Mix(val mix: PersonalizedMix) : LumeRoute
    data object Releases : LumeRoute
    data object Downloads : LumeRoute
    data object Replay : LumeRoute
    data object Equalizer : LumeRoute
    data object Settings : LumeRoute
    data class Tracks(val title: String, val tracks: List<Track>) : LumeRoute
    data class Albums(val title: String, val albums: List<AlbumShowcase>) : LumeRoute
    data class Artists(val title: String, val artists: List<ArtistInfo>) : LumeRoute
}

/** Estado global de navegação e UI (porta de AppModel do RootView.swift). */
object AppModel {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var tab by mutableStateOf(AppTab.HOME)
    val stacks: Map<AppTab, androidx.compose.runtime.snapshots.SnapshotStateList<LumeRoute>> =
        AppTab.entries.associateWith { mutableStateListOf() }
    var navDirection by mutableIntStateOf(1)

    var feed by mutableStateOf<DiscoverFeed?>(null); private set
    var loadingFeed by mutableStateOf(false); private set
    var artistReleases by mutableStateOf<List<AlbumShowcase>>(emptyList()); private set

    var showPlayer by mutableStateOf(false)
    var playerTab by mutableStateOf(PlayerSurfaceTab.ARTWORK)
    var showQueue by mutableStateOf(false)
    var showCoverFlow by mutableStateOf(false)
    var playlistPickerTrack by mutableStateOf<Track?>(null)
    var menuTrack by mutableStateOf<Track?>(null)
    var menuQueue by mutableStateOf<List<Track>?>(null)
    var toast by mutableStateOf<String?>(null)
    var searchFocusToken by mutableIntStateOf(0)
    var searchLyricsToken by mutableIntStateOf(0)
    var tabletSheet by mutableStateOf<String?>(null)

    private var lastFeedLoad = 0L

    /** Aparência: "auto" (sistema), "light" ou "dark". */
    var appearance by mutableStateOf("auto"); private set

    fun loadPrefs(ctx: android.content.Context) {
        appearance = ctx.getSharedPreferences("lume_prefs", android.content.Context.MODE_PRIVATE).getString("appearance", "auto") ?: "auto"
    }

    fun setAppearance(ctx: android.content.Context, v: String) {
        appearance = v
        ctx.getSharedPreferences("lume_prefs", android.content.Context.MODE_PRIVATE).edit().putString("appearance", v).apply()
    }

    val hasUnseenReleases: Boolean get() = artistReleases.any { it.id !in LibraryStore.seenReleaseIds }
    fun markReleasesSeen() { LibraryStore.markReleasesSeen(artistReleases.map { it.id }) }

    /** Estilo escolhido nos Ajustes para o palco do Tocando agora (nunca "Letra"). */
    var playerStyle: PlayerSurfaceTab
        get() = LibraryStore.playerSurface.let { if (it == PlayerSurfaceTab.LYRICS) PlayerSurfaceTab.ARTWORK else it }
        set(v) { LibraryStore.playerSurface = if (v == PlayerSurfaceTab.LYRICS) PlayerSurfaceTab.ARTWORK else v; if (playerTab != PlayerSurfaceTab.LYRICS) playerTab = LibraryStore.playerSurface }

    val currentStack get() = stacks.getValue(tab)

    fun push(route: LumeRoute) { navDirection = 1; currentStack.add(route) }

    fun pop(): Boolean {
        val st = currentStack
        if (st.isNotEmpty()) { navDirection = -1; st.removeAt(st.lastIndex); return true }
        return false
    }

    fun select(t: AppTab) {
        Haptics.selection()
        if (tab == t) {
            stacks.getValue(t).clear()
            if (t == AppTab.SEARCH) searchFocusToken++
        } else {
            tab = t
            if (t == AppTab.SEARCH) searchFocusToken++
        }
    }

    fun openLyricsSearch() { tab = AppTab.SEARCH; stacks.getValue(AppTab.SEARCH).clear(); searchLyricsToken++; searchFocusToken++ }

    fun navigateFromPlayer(route: LumeRoute) {
        showPlayer = false
        scope.launch { delay(300); push(route) }
    }

    fun openArtist(name: String, deezerId: Long? = null) = push(LumeRoute.Artist(LibraryStore.mainArtist(name), deezerId))

    // ---------- Feed ----------

    suspend fun loadFeed(force: Boolean = false) {
        if (feed == null) DiscoveryService.cachedFeed()?.let { feed = it }
        if (!force && System.currentTimeMillis() - lastFeedLoad < 600_000L && feed != null) return
        loadingFeed = feed == null
        val fresh = if (force) DiscoveryService.refresh() else DiscoveryService.feed()
        feed = fresh
        loadingFeed = false
        lastFeedLoad = System.currentTimeMillis()
    }

    suspend fun refreshArtistReleases() {
        var names = LibraryStore.topListenedArtists.take(12)
        if (names.isEmpty()) names = feed?.topArtists?.take(6)?.map { it.name } ?: emptyList()
        if (names.isEmpty()) return
        val found = DiscoveryService.newReleases(names)
        if (found.isNotEmpty()) artistReleases = found
    }

    // ---------- Player helpers ----------

    fun openPlayer(mode: PlayerSurfaceTab? = null) {
        if (mode != null) playerTab = mode else if (playerTab != PlayerSurfaceTab.LYRICS) playerTab = playerStyle
        if (AudioPlayer.currentTrack == null) {
            val list = feed?.topBrazil ?: emptyList()
            if (list.isNotEmpty()) AudioPlayer.play(list.first(), list) else { showToast("Escolha uma música para começar"); return }
        }
        showPlayer = true
    }

    /** "Lume Flow": rádio infinita a partir do que você ama. */
    fun startFlow() {
        var seeds = LibraryStore.mostPlayedTracks.take(12) + LibraryStore.favoriteTracks.take(12) + LibraryStore.recentTracks.take(8)
        if (seeds.isEmpty()) seeds = (feed?.topBrazil ?: emptyList()).take(15)
        val seed = seeds.randomOrNull()
        if (seed == null) { showToast("Carregando as paradas… tente de novo em instantes"); return }
        AudioPlayer.autoplayRadio = true
        AudioPlayer.play(seed, listOf(seed))
        showToast("Lume Flow ligado · rádio infinita a partir de ${seed.artist}")
        showPlayer = true
    }

    fun showTrackMenu(track: Track, queue: List<Track>? = null) { menuTrack = track; menuQueue = queue }

    fun showToast(text: String) {
        toast = text
        scope.launch { delay(2800); if (toast == text) toast = null }
    }
}
