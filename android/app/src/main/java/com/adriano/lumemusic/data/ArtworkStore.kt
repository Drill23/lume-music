package com.adriano.lumemusic.data

import androidx.compose.runtime.mutableStateMapOf
import com.adriano.lumemusic.engine.ArtworkResolver

/** Capas hi-res (upgrade de thumbs do YouTube) e fotos de artistas, observáveis pelo Compose. */
object ArtworkStore {
    private val upgraded = mutableStateMapOf<String, String>()      // track id -> capa hi-res
    private val artistPhotos = mutableStateMapOf<String, String>()  // artista minúsculo -> foto
    private val pending = HashSet<String>()
    private val pendingArtists = HashSet<String>()
    private val missingArtists = HashSet<String>()

    fun url(t: Track): String {
        upgraded[t.id]?.let { return it }
        val stored = LibraryStore.tracksById[t.id]?.artworkURL
        if (stored != null && !ArtworkResolver.needsUpgrade(stored)) return stored
        return t.artworkURL
    }

    suspend fun ensure(t: Track) {
        if (upgraded[t.id] != null || !ArtworkResolver.needsUpgrade(url(t))) return
        synchronized(pending) { if (!pending.add(t.id)) return }
        try {
            val cover = ArtworkResolver.albumCover(t.title, LibraryStore.mainArtist(t.artist), t.album)
            if (cover != null) {
                upgraded[t.id] = cover
                LibraryStore.updateArtwork(cover, t.id)
            }
        } finally { synchronized(pending) { pending.remove(t.id) } }
    }

    fun photo(artist: String): String? = artistPhotos[LibraryStore.mainArtist(artist).lowercase()]

    fun register(artists: List<ArtistInfo>) {
        for (a in artists) if (a.pictureURL.isNotEmpty()) artistPhotos[a.name.lowercase()] = a.pictureURL
    }

    suspend fun ensurePhoto(artist: String) {
        val name = LibraryStore.mainArtist(artist)
        val key = name.lowercase()
        if (key.isEmpty() || artistPhotos[key] != null || key in missingArtists) return
        synchronized(pendingArtists) { if (!pendingArtists.add(key)) return }
        try {
            val url = ArtworkResolver.artistPicture(name)
            if (url != null) artistPhotos[key] = url else missingArtists.add(key)
        } finally { synchronized(pendingArtists) { pendingArtists.remove(key) } }
    }
}
