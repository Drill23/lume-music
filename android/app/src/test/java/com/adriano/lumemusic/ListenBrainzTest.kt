package com.adriano.lumemusic

import com.adriano.lumemusic.data.ListenPayload
import com.adriano.lumemusic.data.ListenRule
import com.adriano.lumemusic.data.PendingListen
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListenBrainzTest {
    @Test fun halfOfTheTrackCounts() {
        assertFalse(ListenRule.shouldSubmit(200.0, 99.0))
        assertTrue(ListenRule.shouldSubmit(200.0, 100.0))
        assertTrue(ListenRule.shouldSubmit(60.0, 30.0))
    }

    @Test fun fourMinutesCapsLongTracks() {
        assertFalse(ListenRule.shouldSubmit(900.0, 239.0))
        assertTrue(ListenRule.shouldSubmit(900.0, 240.0))   // metade seria 450 s
        assertTrue(ListenRule.shouldSubmit(481.0, 240.0))
    }

    @Test fun tracksUnder30SecondsNeverCount() {
        assertFalse(ListenRule.shouldSubmit(29.9, 29.9))
        assertFalse(ListenRule.shouldSubmit(20.0, 20.0))
        assertTrue(ListenRule.shouldSubmit(30.0, 15.0))
    }

    @Test fun unknownDurationWaitsForFourMinutes() {
        assertFalse(ListenRule.shouldSubmit(0.0, 120.0))
        assertTrue(ListenRule.shouldSubmit(0.0, 240.0))
    }

    @Test fun singlePayloadFollowsTheContract() {
        val l = PendingListen(1764270000, "Anitta", "Envolver", "Versions of Me", "abc123DEF45", 213_000)
        val o = Json.parseToJsonElement(ListenPayload.body("single", listOf(l), "5.2.0")).jsonObject
        assertEquals("single", o["listen_type"]!!.jsonPrimitive.content)
        val item = (o["payload"] as JsonArray)[0] as JsonObject
        assertEquals("1764270000", item["listened_at"]!!.jsonPrimitive.content)
        val md = item["track_metadata"]!!.jsonObject
        assertEquals("Anitta", md["artist_name"]!!.jsonPrimitive.content)
        assertEquals("Envolver", md["track_name"]!!.jsonPrimitive.content)
        assertEquals("Versions of Me", md["release_name"]!!.jsonPrimitive.content)
        val info = md["additional_info"]!!.jsonObject
        assertEquals("Lume Music", info["media_player"]!!.jsonPrimitive.content)
        assertEquals("Lume Music", info["submission_client"]!!.jsonPrimitive.content)
        assertEquals("5.2.0", info["submission_client_version"]!!.jsonPrimitive.content)
        assertEquals("youtube.com", info["music_service"]!!.jsonPrimitive.content)
        assertEquals("https://music.youtube.com/watch?v=abc123DEF45", info["origin_url"]!!.jsonPrimitive.content)
        assertEquals("213000", info["duration_ms"]!!.jsonPrimitive.content)
    }

    @Test fun playingNowHasNoListenedAtAndOptionalFieldsAreOmitted() {
        val l = PendingListen(1, "A", "T")
        val o = Json.parseToJsonElement(ListenPayload.body("playing_now", listOf(l), "5.2.0")).jsonObject
        val item = (o["payload"] as JsonArray)[0] as JsonObject
        assertNull(item["listened_at"])
        val md = item["track_metadata"]!!.jsonObject
        assertNull(md["release_name"])
        assertNull(md["additional_info"]!!.jsonObject["origin_url"])
    }

    @Test fun importCarriesManyListens() {
        val ls = (1..3).map { PendingListen(it.toLong(), "A$it", "T$it") }
        val o = Json.parseToJsonElement(ListenPayload.body("import", ls, "5.2.0")).jsonObject
        assertEquals("import", o["listen_type"]!!.jsonPrimitive.content)
        assertEquals(3, (o["payload"] as JsonArray).size)
    }
}
