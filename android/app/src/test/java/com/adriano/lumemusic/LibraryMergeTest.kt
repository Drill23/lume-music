package com.adriano.lumemusic

import com.adriano.lumemusic.data.BackupText
import com.adriano.lumemusic.data.LbDeleted
import com.adriano.lumemusic.data.LbPlaylist
import com.adriano.lumemusic.data.LbTrack
import com.adriano.lumemusic.data.LibraryMerge
import com.adriano.lumemusic.data.LibraryV1
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class LibraryMergeTest {
    private fun t(id: String, title: String = id) = LbTrack(id, title, "Artista")
    private fun pl(id: String, updated: Long, vararg tracks: String, name: String = id) =
        LbPlaylist(id, name, 1000, updated, tracks.map { t(it) })
    private fun lib(
        playlists: List<LbPlaylist> = emptyList(), liked: List<LbTrack> = emptyList(),
        followed: List<String> = emptyList(), deleted: List<LbDeleted> = emptyList(),
    ) = LibraryV1(exportedAt = 5000, platform = "android", app = "5.2.0", playlists = playlists, liked = liked, followed = followed, deletedPlaylists = deleted)

    @Test fun playlistsAreUnitedById() {
        val m = LibraryMerge.merge(lib(playlists = listOf(pl("a", 10, "x"))), lib(playlists = listOf(pl("b", 20, "y"))))
        assertEquals(listOf("a", "b"), m.playlists.map { it.id })
    }

    @Test fun sameIdKeepsTheMostRecentlyUpdated() {
        val local = lib(playlists = listOf(pl("a", 10, "x", name = "Local"), pl("c", 50, "z", name = "LocalC")))
        val remote = lib(playlists = listOf(pl("a", 30, "x", "y", name = "Remota"), pl("c", 40, "q", name = "RemotaC")))
        val m = LibraryMerge.merge(local, remote)
        val a = m.playlists.first { it.id == "a" }
        assertEquals("Remota", a.name)
        assertEquals(listOf("x", "y"), a.tracks.map { it.videoId })
        assertEquals("LocalC", m.playlists.first { it.id == "c" }.name)
        // a ordem local é preservada
        assertEquals(listOf("a", "c"), m.playlists.map { it.id })
    }

    @Test fun tieOnUpdatedKeepsLocal() {
        val m = LibraryMerge.merge(lib(playlists = listOf(pl("a", 10, "x", name = "Local"))), lib(playlists = listOf(pl("a", 10, "y", name = "Remota"))))
        assertEquals("Local", m.playlists.single().name)
    }

    @Test fun deletedPlaylistDoesNotComeBackWhenDeletedAfterLastUpdate() {
        val local = lib(deleted = listOf(LbDeleted("a", 100)))
        val remote = lib(playlists = listOf(pl("a", 50, "x"), pl("b", 50, "y")))
        val m = LibraryMerge.merge(local, remote)
        assertEquals(listOf("b"), m.playlists.map { it.id })
        assertEquals(listOf("a"), m.deletedPlaylists.map { it.id })
    }

    @Test fun playlistEditedAfterDeletionSurvives() {
        val local = lib(deleted = listOf(LbDeleted("a", 100)))
        val remote = lib(playlists = listOf(pl("a", 200, "x")))
        val m = LibraryMerge.merge(local, remote)
        assertEquals(listOf("a"), m.playlists.map { it.id })
        assertTrue(m.deletedPlaylists.isEmpty())   // lápide velha descartada
    }

    @Test fun deletionFromRemoteAlsoRemovesOlderLocalPlaylist() {
        val m = LibraryMerge.merge(lib(playlists = listOf(pl("a", 50, "x"))), lib(deleted = listOf(LbDeleted("a", 100))))
        assertTrue(m.playlists.isEmpty())
    }

    @Test fun tombstonesAreUnitedKeepingTheLatest() {
        val m = LibraryMerge.merge(lib(deleted = listOf(LbDeleted("a", 100), LbDeleted("b", 5))), lib(deleted = listOf(LbDeleted("a", 300), LbDeleted("c", 7))))
        assertEquals(mapOf("a" to 300L, "b" to 5L, "c" to 7L), m.deletedPlaylists.associate { it.id to it.at })
    }

    @Test fun likedIsUnitedByVideoIdKeepingLocalOrder() {
        val local = lib(liked = listOf(t("v3"), t("v1")))
        val remote = lib(liked = listOf(t("v1", "outro título"), t("v2"), t("v3")))
        val m = LibraryMerge.merge(local, remote)
        assertEquals(listOf("v3", "v1", "v2"), m.liked.map { it.videoId })
        assertEquals("v1", m.liked[1].title)   // mantém a versão local
    }

    @Test fun followedIsUnitedIgnoringCase() {
        val m = LibraryMerge.merge(lib(followed = listOf("Anitta", "Pabllo Vittar")), lib(followed = listOf("anitta", "ANITTA", "Ludmilla", " ")))
        assertEquals(listOf("Anitta", "Pabllo Vittar", "Ludmilla"), m.followed)
    }

    @Test fun mergeWithEmptyRemoteNeverLosesAnything() {
        val local = lib(playlists = listOf(pl("a", 10, "x")), liked = listOf(t("v1")), followed = listOf("Anitta"))
        val m = LibraryMerge.merge(local, lib())
        assertEquals(local.playlists, m.playlists); assertEquals(local.liked, m.liked); assertEquals(local.followed, m.followed)
    }

    @Test fun jsonRoundTripAndContractFormat() {
        val l = lib(playlists = listOf(LbPlaylist("p1", "Minha", 1, 2, listOf(LbTrack("dQw4w9WgXcQ", "T", "A", "Alb", 213, "https://x/y.jpg")))), liked = listOf(t("v1")), followed = listOf("Anitta"), deleted = listOf(LbDeleted("z", 9)))
        val o = l.toJsonObject()
        assertEquals("1", o["v"].toString())
        val back = LibraryV1.fromJsonObject(Json.parseToJsonElement(o.toString()) as JsonObject)!!
        assertEquals(l.playlists, back.playlists); assertEquals(l.liked.map { it.videoId }, back.liked.map { it.videoId })
        assertEquals(l.followed, back.followed); assertEquals(l.deletedPlaylists, back.deletedPlaylists)
        assertEquals(213, back.playlists[0].tracks[0].durationSec)
    }

    @Test fun fromJsonRejectsWrongVersionAndToleratesLooseTypes() {
        assertNull(LibraryV1.fromJsonObject(Json.parseToJsonElement("""{"v":2}""") as JsonObject))
        assertNull(LibraryV1.fromJsonObject(Json.parseToJsonElement("""{"playlists":[]}""") as JsonObject))
        val ios = LibraryV1.fromJsonObject(Json.parseToJsonElement(
            """{"v":1,"exportedAt":"1764270000000","platform":"ios","playlists":[{"id":"u1","name":"P","created":1,"updated":2.0,"tracks":[{"videoId":"a","title":"T","artist":"A","durationSec":"213"},{"title":"sem id"}]}],"liked":[],"followed":["X",null]}""") as JsonObject)
        assertNotNull(ios)
        assertEquals(1764270000000, ios!!.exportedAt)
        assertEquals(1, ios.playlists[0].tracks.size)
        assertEquals(213, ios.playlists[0].tracks[0].durationSec)
        assertEquals(2L, ios.playlists[0].updated)
        assertEquals(listOf("X"), ios.followed)
        assertFalse(ios.isEmpty)
    }

    @Test fun lastBackupText() {
        val tz = TimeZone.getTimeZone("America/Sao_Paulo")
        fun at(h: Int, m: Int, day: Int) = java.util.Calendar.getInstance(tz).apply { set(2026, 10, day, h, m, 0); set(java.util.Calendar.MILLISECOND, 0) }.timeInMillis
        val now = at(22, 0, 27)
        assertEquals("Último backup: hoje às 21:40", BackupText.last(at(21, 40, 27), now, tz))
        assertEquals("Último backup: ontem às 23:05", BackupText.last(at(23, 5, 26), now, tz))
        assertEquals("Último backup: 20/11 às 08:00", BackupText.last(at(8, 0, 20), now, tz))
        assertEquals("Nenhum backup ainda", BackupText.last(0, now, tz))
    }
}
