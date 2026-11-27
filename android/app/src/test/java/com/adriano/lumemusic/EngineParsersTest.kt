package com.adriano.lumemusic

import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.DiscText
import com.adriano.lumemusic.engine.InnerTube
import com.adriano.lumemusic.engine.LumeJson
import com.adriano.lumemusic.engine.LyricsService
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.engine.SearchService
import com.adriano.lumemusic.engine.get
import com.adriano.lumemusic.engine.int
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EngineParsersTest {
    private val searchJson = """
    {"contents":{"tabbedSearchResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[
      {"musicShelfRenderer":{"contents":[
        {"musicResponsiveListItemRenderer":{
          "playlistItemData":{"videoId":"dQw4w9WgXcQ"},
          "thumbnail":{"musicThumbnailRenderer":{"thumbnail":{"thumbnails":[
             {"url":"https://lh3.googleusercontent.com/abc=w60-h60-l90-rj","width":60},
             {"url":"https://lh3.googleusercontent.com/abc=w226-h226-l90-rj","width":226}]}}},
          "flexColumns":[
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Never Gonna Give You Up"}]}}},
            {"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Música"},{"text":" • "},{"text":"Rick Astley"},{"text":" • "},{"text":"Whenever You Need Somebody"},{"text":" • "},{"text":"3:33"}]}}}
          ]}}
      ]}}]}}}}]}}}
    """.trimIndent()

    @Test fun parsesSearchResults() {
        val tracks = InnerTube.extractResponsiveListTracks(Json.parseToJsonElement(searchJson), "YouTube Music")
        assertEquals(1, tracks.size)
        val t = tracks[0]
        assertEquals("dQw4w9WgXcQ", t.videoId)
        assertEquals("Never Gonna Give You Up", t.title)
        assertEquals("Rick Astley", t.artist)
        assertEquals("Whenever You Need Somebody", t.album)
        assertEquals(213.0, t.duration, 0.01)
        assertTrue(t.artworkURL.contains("=w1200-h1200-l95-rj"))
        assertEquals("3:33", t.formattedDuration)
    }

    @Test fun parsesRadioPanel() {
        val j = """{"contents":{"x":[{"playlistPanelVideoRenderer":{"videoId":"abcdefghijk","title":{"runs":[{"text":"Song"}]},
          "longBylineText":{"runs":[{"text":"Artist"},{"text":" • "},{"text":"Album"}]},"lengthText":{"runs":[{"text":"1:05:00"}]},
          "thumbnail":{"thumbnails":[{"url":"https://i.ytimg.com/a.jpg","width":120}]}}}]}}"""
        val r = InnerTube.extractPanelVideoTracks(Json.parseToJsonElement(j))
        assertEquals(1, r.size)
        assertEquals("Artist", r[0].artist)
        assertEquals("Album", r[0].album)
        assertEquals(3900.0, r[0].duration, 0.01)
    }

    @Test fun parseClock() {
        assertEquals(75.0, InnerTube.parseClock("1:15")!!, 0.0)
        assertNull(InnerTube.parseClock("abc"))
    }

    @Test fun picksItag18FirstThenFallsBackTo140() {
        val both = Json.parseToJsonElement("""{"streamingData":{"formats":[{"itag":18,"url":"https://a/18","mimeType":"video/mp4","bitrate":444000}],
          "adaptiveFormats":[{"itag":251,"url":"https://a/251"},{"itag":140,"url":"https://a/140","bitrate":130000}]}}""")
        assertEquals("https://a/18", MusicEngine.pickProgressive(both)!!.first)
        val only140 = Json.parseToJsonElement("""{"streamingData":{"adaptiveFormats":[{"itag":251,"url":"https://a/251"},{"itag":140,"url":"https://a/140","bitrate":130000}]}}""")
        assertEquals(140, MusicEngine.pickProgressive(only140)!!.third)
        val only18 = Json.parseToJsonElement("""{"streamingData":{"formats":[{"itag":18,"url":"https://a/18","mimeType":"video/mp4","bitrate":444000}]}}""")
        val p = MusicEngine.pickProgressive(only18)!!
        assertEquals("https://a/18", p.first); assertEquals(18, p.third)
        assertNull(MusicEngine.pickProgressive(Json.parseToJsonElement("""{"playabilityStatus":{"status":"ERROR"}}""")))
    }

    @Test fun stableIdMatchesIosFnv() {
        // FNV-1a 64 de "artist::title" — mesmo algoritmo do iOS
        val id = Track.stableId("Title", "Artist")
        assertTrue(id.startsWith("tr_") && id.length == 19)
        assertEquals(id, Track.stableId(" title ", " ARTIST "))
    }

    @Test fun lrcParsing() {
        val lrc = "[ar:x]\n[00:01.50]Primeira\n[00:05.00]Segunda\n[00:03]  \n[01:02.5][01:30.25]Repete"
        val l = LyricsService.parseLRC(lrc)
        assertEquals(5, l.size)
        assertEquals(1.5, l[0].time, 0.001)
        assertEquals("♪", l[1].text)
        assertEquals(62.5, l[3].time, 0.001)
        assertEquals("Repete", l[4].text)
        assertTrue(l.zipWithNext().all { it.first.time <= it.second.time })
    }

    @Test fun lyricsValidation() {
        assertFalse(LyricsService.usable(listOf("a", "b")))
        assertFalse(LyricsService.usable(listOf("Instrumental", "x", "y")))
        assertTrue(LyricsService.usable(listOf("a", "b", "c")))
        assertNotNull(LyricsService.plainLines("um\ndois\ntrês"))
        assertNull(LyricsService.plainLines("[Chorus]\num"))
    }

    @Test fun titleAndArtistCleaning() {
        assertEquals("Música", LyricsService.cleanTitle("Música (Official Video)"))
        assertEquals("Música", LyricsService.cleanTitle("Música - Ao Vivo em SP"))
        assertEquals("Música", LyricsService.cleanTitle("Música [HD]"))
        assertEquals("Artista", LyricsService.cleanArtist("Artista - Topic"))
        assertEquals("Jorge", LyricsService.cleanArtist("Jorge & Mateus"))
    }

    @Test fun textNormalizationAndMatching() {
        assertEquals("coracao", DiscText.normalize("Coração (feat. X)"))
        assertTrue(DiscText.artistMatches("Henrique & Juliano", "Henrique e Juliano"))
        assertTrue(DiscText.titleLooselyMatches("Lose Yourself", "Lose Yourself - Remastered"))
        assertFalse(DiscText.titleMatches("A", "B"))
    }

    @Test fun snippetExtraction() {
        val s = SearchService.extractSnippet("amor eterno", "linha um\nfala de amor eterno\ntres\nquatro", "")
        assertEquals("fala de amor eterno / tres", s)
    }

    @Test fun jsonHelpersTolerateNumbers() {
        val e = LumeJson.parseToJsonElement("""{"a":"12","b":3.0}""")
        assertEquals(12, e["a"].int())
    }
}
