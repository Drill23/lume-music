package com.adriano.lumemusic

import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.ChartList
import com.adriano.lumemusic.engine.ChartParsers
import com.adriano.lumemusic.engine.ChartPlace
import com.adriano.lumemusic.engine.GenreSources
import com.adriano.lumemusic.data.DiscoverFeed
import com.adriano.lumemusic.data.newTrack
import com.adriano.lumemusic.engine.LumeJson
import com.adriano.lumemusic.ui.OnboardingGenres
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeEngineTest {
    @Test fun chartPlacesMatchIos() {
        assertEquals(20, ChartPlace.all.size)
        assertEquals(listOf("br", "world", "us", "gb"), ChartPlace.all.take(4).map { it.id })
        assertEquals(3155776842L, ChartPlace.world.deezerPlaylist)
        assertEquals("Top 10 Global", ChartPlace.world.title)
        assertEquals("Top 10 Brasil", ChartPlace.all[0].title)
        assertEquals("EUA", ChartPlace.place("us")!!.short)
        assertEquals("ZZ", ChartPlace.world.chartCountry.ytmCode)
    }

    @Test fun genreSourcesUseCorrectedAppleIds() {
        fun ids(id: String) = GenreSources.sources(MusicGenre.all.first { it.id == id }).map { it.country to it.id }
        assertEquals(listOf("br" to 1228), ids("sertanejo"))
        assertEquals(listOf("br" to 1229, "br" to 18), ids("funk_br"))
        assertEquals(listOf("br" to 1226, "br" to 1227), ids("pagode"))
        assertEquals(listOf("br" to 1225, "br" to 1221), ids("mpb"))
        assertEquals(listOf("br" to 1223), ids("forro"))
        assertEquals(listOf("us" to 51), ids("kpop"))
        assertEquals(listOf("us" to 14), ids("pop"))
    }

    @Test fun interleaveAlternatesAndDedupes() {
        val out = GenreSources.interleave(listOf(listOf("a1", "a2", "x"), listOf("b1", "x", "b3")), 10) { it }
        assertEquals(listOf("a1", "b1", "a2", "x", "b3"), out)
        assertEquals(listOf("a1", "b1"), GenreSources.interleave(listOf(listOf("a1", "a2"), listOf("b1", "b2")), 2) { it })
    }

    @Test fun captionShowsSourceAndAge() {
        val now = System.currentTimeMillis()
        assertTrue(ChartList("br", emptyList(), emptyList(), "Apple Music", now).caption.endsWith("atualizado agora"))
        assertEquals("Apple Music · atualizado há 5 min", ChartList("br", emptyList(), emptyList(), "Apple Music", now - 5 * 60_000L).caption)
        assertEquals("há 2 h", ChartList.relativeAgo(now - 2 * 3600_000L, now))
    }

    @Test fun deezerPlaylistRanksArtistsAndAlbums() {
        val json = Json.parseToJsonElement("""{"data":[
          {"title":"A","duration":100,"artist":{"id":1,"name":"One","picture_xl":"p1"},"album":{"id":10,"title":"Alb","cover_xl":"c10","cover_big":"cb10"}},
          {"title":"B","duration":100,"artist":{"id":2,"name":"Two"},"album":{"id":11,"title":"Alb2","cover_xl":"c11"}},
          {"title":"C","duration":100,"artist":{"id":2,"name":"Two"},"album":{"id":11,"title":"Alb2","cover_xl":"c11"}},
          {"title":"D","duration":100,"artist":{"id":2,"name":"Two"},"album":{"id":11,"title":"Alb2","cover_xl":"c11"}}
        ]}""").jsonObject["data"]!!.jsonArray.map { it as JsonObject }
        val r = ChartParsers.deezerPlaylist(data = json)
        assertEquals(4, r.tracks.size)
        assertEquals(listOf("Two", "One"), r.artists.map { it.name })   // 2 faixas > 1 faixa
        assertEquals(listOf(1, 2), r.artists.map { it.rank }.sortedBy { it })
        assertEquals(2, r.albums.size)                                  // álbuns únicos
        assertEquals("dzalb_10", r.albums[0].id)
    }

    @Test fun onboardingGenreAliasesAreTolerant() {
        assertEquals("funk_br", OnboardingGenres.match("Baile Funk")!!.id)
        assertEquals("hiphop", OnboardingGenres.match("Rap")!!.id)
        assertEquals("sertanejo", OnboardingGenres.match("Sertanejo")!!.id)
        assertEquals("kpop", OnboardingGenres.match("K-Pop")!!.id)
        assertEquals("mpb", OnboardingGenres.match("MPB & Bossa")!!.id)
    }

    @Test fun brazilRadarUsesBrazilianHitsWhenPresent() {
        val t = { n: String -> newTrack(title = n, artist = "x") }
        val feed = DiscoverFeed(0, emptyList(), emptyList(), topBrazil = listOf(t("apple")), topGlobal = listOf(t("g")),
            topArtists = emptyList(), trending = emptyList(), brazilianHits = listOf(t("nacional")))
        val mixes = CatalogExplorerService.buildPersonalizedMixes(emptyList(), emptyList(), emptyList(), emptyList(), feed)
        val radar = mixes.first { it.id == "mix_br_radar" }
        assertEquals("nacional", radar.tracks.first().title)
        assertNotNull(mixes.firstOrNull { it.id == "mix_global_wave" })
    }

    @Test fun oldFeedCacheWithoutNewFieldsStillDecodes() {
        val old = """{"updatedAt":1,"newReleases":[],"brazilReleases":[],"topBrazil":[],"topGlobal":[],"topArtists":[],"trending":[]}"""
        val f = LumeJson.decodeFromString(DiscoverFeed.serializer(), old)
        assertEquals(null, f.brazilianHits)
    }
}
