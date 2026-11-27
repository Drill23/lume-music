package com.adriano.lumemusic.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.automirrored.rounded.PlaylistAdd
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material.icons.rounded.Pin
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Album
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.DirectionsCar
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.DownloadDone
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FlightTakeoff
import androidx.compose.material.icons.rounded.FreeBreakfast
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.HeartBroken
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.NewReleases
import androidx.compose.material.icons.rounded.ViewCarousel
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Inventory2
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Landscape
import androidx.compose.material.icons.rounded.Lyrics
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MicExternalOn
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.NotificationsOff
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PersonOutline
import androidx.compose.material.icons.rounded.Piano
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.Radio
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Spa
import androidx.compose.material.icons.rounded.Speaker
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Square
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Voicemail
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material.icons.rounded.WbSunny
import androidx.compose.material.icons.rounded.WbTwilight
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material.icons.rounded.AutoMode
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.Wallpaper
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Mapeia os nomes de SF Symbols usados no app iOS para ícones Material Symbols (Rounded).
 * Assim as telas usam o mesmo vocabulário de nomes nos dois apps.
 */
fun sf(name: String): ImageVector = when (name) {
    "house.fill", "house" -> Icons.Rounded.Home
    "safari.fill", "safari" -> Icons.Rounded.Explore
    "square.stack.fill", "square.stack", "square.stack.3d.forward.dottedline" -> Icons.Rounded.LibraryMusic
    "magnifyingglass" -> Icons.Rounded.Search
    "gearshape", "gearshape.fill" -> Icons.Rounded.Settings
    "play.fill", "play" -> Icons.Rounded.PlayArrow
    "pause.fill", "pause" -> Icons.Rounded.Pause
    "forward.fill" -> Icons.Rounded.SkipNext
    "backward.fill" -> Icons.Rounded.SkipPrevious
    "stop.fill" -> Icons.Rounded.Stop
    "shuffle" -> Icons.Rounded.Shuffle
    "repeat" -> Icons.Rounded.Repeat
    "repeat.1" -> Icons.Rounded.RepeatOne
    "infinity" -> Icons.Rounded.AutoMode
    "heart.fill", "heart", "heart.circle.fill", "heart.circle" -> Icons.Rounded.Favorite
    "heart.slash" -> Icons.Rounded.HeartBroken
    "xmark", "xmark.circle", "xmark.circle.fill" -> Icons.Rounded.Close
    "plus", "text.badge.plus" -> Icons.Rounded.Add
    "plus.circle" -> Icons.Rounded.AddCircle
    "minus.circle.fill" -> Icons.Rounded.Close
    "ellipsis" -> Icons.Rounded.MoreHoriz
    "list.bullet", "music.note.list" -> Icons.AutoMirrored.Rounded.QueueMusic
    "music.note", "music.quarternote.3" -> Icons.Rounded.MusicNote
    "music.mic" -> Icons.Rounded.MicExternalOn
    "music.note.house.fill" -> Icons.Rounded.LibraryMusic
    "arrow.down.circle", "arrow.down.circle.fill", "square.and.arrow.down", "arrow.down" -> Icons.Rounded.Download
    "checkmark.circle.fill", "checkmark.seal.fill" -> Icons.Rounded.CheckCircle
    "checkmark" -> Icons.Rounded.Check
    "square.and.arrow.up" -> Icons.Rounded.IosShare
    "trash" -> Icons.Rounded.Delete
    "pencil" -> Icons.Rounded.Edit
    "clock", "clock.fill" -> Icons.Rounded.History
    "arrow.clockwise" -> Icons.Rounded.Refresh
    "arrow.counterclockwise" -> Icons.Rounded.Replay
    "arrow.up.arrow.down" -> Icons.Rounded.SwapVert
    "arrow.up.left" -> Icons.Rounded.ArrowUpward
    "chevron.down" -> Icons.Rounded.KeyboardArrowDown
    "chevron.up" -> Icons.Rounded.KeyboardArrowUp
    "chevron.right" -> Icons.Rounded.ChevronRight
    "chevron.left" -> Icons.AutoMirrored.Rounded.ArrowBack
    "bell" -> Icons.Rounded.NotificationsActive
    "bell.slash" -> Icons.Rounded.NotificationsOff
    "bolt.fill" -> Icons.Rounded.Bolt
    "flame.fill", "flame" -> Icons.Rounded.LocalFireDepartment
    "sparkles", "sparkles.tv", "wand.and.stars" -> Icons.Rounded.AutoAwesome
    "star.fill" -> Icons.Rounded.Star
    "sun.max.fill", "sun.max.circle.fill", "sun.haze.fill" -> Icons.Rounded.WbSunny
    "moon.stars.fill", "moon.zzz", "moon.zzz.fill" -> Icons.Rounded.Bedtime
    "leaf.fill" -> Icons.Rounded.Spa
    "car.fill" -> Icons.Rounded.DirectionsCar
    "cup.and.saucer.fill" -> Icons.Rounded.FreeBreakfast
    "brain.head.profile" -> Icons.Rounded.Psychology
    "globe.americas.fill" -> Icons.Rounded.Public
    "film.fill" -> Icons.Rounded.Movie
    "pianokeys" -> Icons.Rounded.Piano
    "headphones" -> Icons.Rounded.Headphones
    "guitars.fill" -> Icons.Rounded.MusicNote
    "tropicalstorm" -> Icons.Rounded.WbTwilight
    "speaker.fill", "speaker.wave.3.fill" -> Icons.AutoMirrored.Rounded.VolumeUp
    "waveform", "waveform.path" -> Icons.Rounded.GraphicEq
    "waveform.path.ecg" -> Icons.Rounded.Sensors
    "chart.bar.fill" -> Icons.Rounded.Equalizer
    "chart.line.uptrend.xyaxis" -> Icons.Rounded.TrendingUp
    "circle.hexagongrid.fill" -> Icons.Rounded.Psychology
    "mountain.2.fill" -> Icons.Rounded.Landscape
    "eye.slash" -> Icons.Rounded.CloudOff
    "slider.horizontal.3", "slider.vertical.3" -> Icons.Rounded.Tune
    "dial.medium" -> Icons.Rounded.Speed
    "dot.radiowaves.left.and.right" -> Icons.Rounded.Radio
    "quote.bubble", "quote.bubble.fill" -> Icons.Rounded.Lyrics
    "translate" -> Icons.Rounded.Translate
    "record.circle", "compactdisc" -> Icons.Rounded.Album
    "recordingtape" -> Icons.Rounded.Voicemail
    "square.fill", "cube" -> Icons.Rounded.Square
    "person.fill" -> Icons.Rounded.Person
    "person.2" -> Icons.Rounded.Groups
    "paintpalette", "paintpalette.fill" -> Icons.Rounded.Palette
    "photo.on.rectangle.angled" -> Icons.Rounded.Wallpaper
    "link" -> Icons.Rounded.Link
    "info.circle" -> Icons.Rounded.Info
    "airplane", "airplane.circle", "airplane.circle.fill" -> Icons.Rounded.FlightTakeoff
    "wifi.exclamationmark" -> Icons.Rounded.WifiOff
    "exclamationmark.triangle.fill" -> Icons.Rounded.WarningAmber
    "eject.fill" -> Icons.Rounded.ArrowUpward
    "e.square.fill" -> Icons.Rounded.Square
    "text.line.first.and.arrowtriangle.forward" -> Icons.AutoMirrored.Rounded.PlaylistAdd
    "text.line.last.and.arrowtriangle.forward" -> Icons.AutoMirrored.Rounded.PlaylistAdd
    "doc.on.doc" -> Icons.Rounded.ContentCopy
    "lock.fill" -> Icons.Rounded.Lock
    "key.fill" -> Icons.Rounded.Key
    "arrow.left.arrow.right" -> Icons.Rounded.SwapHoriz
    "system.update" -> Icons.Rounded.SystemUpdate
    "pin" -> Icons.Rounded.Pin
    "cloud" -> Icons.Rounded.Cloud
    "cloud.download" -> Icons.Rounded.CloudDownload
    "arrow.down.circle.done" -> Icons.Rounded.DownloadDone
    "bookmark" -> Icons.Rounded.Bookmark
    "storage" -> Icons.Rounded.Storage
    "speaker.box" -> Icons.Rounded.Speaker
    "inventory" -> Icons.Rounded.Inventory2
    "person.outline" -> Icons.Rounded.PersonOutline
    "arrow.down.line" -> Icons.Rounded.ArrowDownward
    "dark" -> Icons.Rounded.DarkMode
    "arrow.right" -> Icons.AutoMirrored.Rounded.ArrowForward
    "square.grid.2x2.fill" -> Icons.Rounded.GridView
    "sparkles.rectangle.stack.fill" -> Icons.Rounded.NewReleases
    "square.stack.3d.down.right.fill" -> Icons.Rounded.ViewCarousel
    else -> Icons.Rounded.MusicNote
}
