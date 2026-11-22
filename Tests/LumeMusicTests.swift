import Foundation

@main
struct LumeMusicTests {
  static func main() async {
    var passed = 0
    func expect(_ cond: Bool, _ msg: String) {
      if !cond { fputs("FAIL: \(msg)\n", stderr); exit(1) }
      passed += 1
    }

    // 1. Track stableId determinism & normalization
    let id1 = Track.stableId(title: "  Blinding Lights ", artist: "The Weeknd")
    let id2 = Track.stableId(title: "blinding lights", artist: "the weeknd ")
    expect(id1 == id2 && id1.hasPrefix("tr_"), "Track.stableId deterministic")

    // 2. Clock parsing
    expect(MusicEngine.parseClock("3:20") == 200, "parseClock mm:ss")
    expect(MusicEngine.parseClock("1:02:05") == 3725, "parseClock hh:mm:ss")
    expect(MusicEngine.parseClock("abc") == nil, "parseClock invalid")

    // 3. LRC Synced lyrics parsing
    let sampleLRC = """
    [00:12.50]I've been tryna call
    [00:15.20]I've been on my own for long enough
    [01:02.00]Ooh, I'm blinded by the lights
    """
    let lines = LyricsService.parseLRC(sampleLRC)
    expect(lines.count == 3, "parseLRC count")
    expect(abs(lines[0].time - 12.5) < 0.01 && lines[0].text == "I've been tryna call", "parseLRC line 0")
    expect(abs(lines[2].time - 62.0) < 0.01, "parseLRC line 2")

    // 4. Title & Artist cleanup for better lyrics matches
    expect(LyricsService.cleanTitle("Blinding Lights (Official Audio) [HD]") == "Blinding Lights", "cleanTitle strips tags")
    expect(LyricsService.cleanArtist("The Weeknd - Topic") == "The Weeknd", "cleanArtist strips Topic")

    // 5. RepeatMode cycling
    expect(RepeatMode.off.next == .all && RepeatMode.all.next == .one && RepeatMode.one.next == .off, "RepeatMode cycle")

    // 6. Plain text / M3U import parsing
    let text = """
    #EXTM3U
    #EXTINF:200,The Weeknd - Blinding Lights
    https://ignored.example/stream.mp3
    Daft Punk - Instant Crush
    Bohemian Rhapsody
    """
    let res = await ImportService.shared.importFromText(text, name: "Teste")
    expect(res.tracks.count == 3, "Import text track count")
    expect(res.tracks[0].artist == "The Weeknd" && res.tracks[0].title == "Blinding Lights", "M3U EXTINF parse")
    expect(res.tracks[1].artist == "Daft Punk" && res.tracks[1].title == "Instant Crush", "Text Artist - Title parse")
    expect(res.tracks[2].title == "Bohemian Rhapsody", "Plain title parse")

    print("ALL \(passed) LUME MUSIC UNIT TESTS PASSED!")
  }
}
