package com.adriano.lumemusic.ui.screens

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.engine.ImportException
import com.adriano.lumemusic.engine.ImportService
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.keyboardDismissing
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.hex
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Painel visual de importação (paridade 100% com ImportHub.swift do iOS):
 * - Destaque 1-toque: Músicas do aparelho (equivalente ao Apple Music no iPhone)
 * - Grade 2 colunas: Spotify, YouTube Music, Deezer, Apple Music, Amazon Music, Tidal, Arquivo (CSV/M3U/TXT)
 * - Folha guiada por serviço com "Abrir app", detecção automática de link copiado e botão "Colar e importar"
 * - Suporta vários links de uma vez (um por linha) e salva automaticamente na biblioteca.
 */
enum class ImportServiceKind(
    val title: String,
    val tagline: String,
    val symbol: String,
    val hexA: Long,
    val hexB: Long,
    val openUrl: String?,
    val howTo: List<String>,
) {
    DEVICE(
        "Músicas do celular", "1 toque · biblioteca deste Android", "music.note",
        0xFF5A74, 0xFA2D48, null, emptyList(),
    ),
    SPOTIFY(
        "Spotify", "Colar link ou vários links", "dot.radiowaves.left.and.right",
        0x3DDC84, 0x14A44D, "https://open.spotify.com",
        listOf(
            "Abra o Spotify e entre na playlist (ela precisa estar pública).",
            "Toque em ••• › Compartilhar › Copiar link.",
            "Volte aqui e toque em “Colar link e importar”. Você também pode colar vários links de uma vez (um por linha) ou exportar tudo em CSV pelo site Exportify e usar “Arquivo”.",
        ),
    ),
    YOUTUBE_MUSIC(
        "YouTube Music", "Colar link da playlist", "play.fill",
        0xFF5E5E, 0xE00000, "https://music.youtube.com",
        listOf(
            "Abra o YouTube Music e entre na playlist (pública ou não listada).",
            "Toque em Compartilhar › Copiar link.",
            "Volte aqui e toque em “Colar link e importar”.",
        ),
    ),
    DEEZER(
        "Deezer", "Colar link da playlist", "chart.bar.fill",
        0xB86BFF, 0x7B2FF2, "https://www.deezer.com",
        listOf(
            "Abra o Deezer e entre na playlist ou álbum.",
            "Toque em ••• › Compartilhar › Copiar link.",
            "Volte aqui e toque em “Colar link e importar”.",
        ),
    ),
    APPLE_MUSIC(
        "Apple Music", "Colar link da playlist", "music.note.list",
        0xFF5A74, 0xFA2D48, "https://music.apple.com",
        listOf(
            "Abra o Apple Music e entre na playlist ou álbum público.",
            "Toque em ••• › Compartilhar › Copiar link.",
            "Volte aqui e toque em “Colar link e importar”.",
        ),
    ),
    AMAZON_MUSIC(
        "Amazon Music", "Colar link ou CSV", "waveform",
        0x4FE3F0, 0x1AA7D6, "https://music.amazon.com.br",
        listOf(
            "Abra o Amazon Music e entre na playlist.",
            "Toque em Compartilhar › Copiar link.",
            "Volte aqui e cole. Se a Amazon bloquear, exporte em CSV e use “Arquivo”.",
        ),
    ),
    TIDAL(
        "Tidal", "Colar link ou CSV", "sparkles",
        0x6B7280, 0x111827, "https://listen.tidal.com",
        listOf(
            "Abra o Tidal e entre na playlist.",
            "Toque em ••• › Compartilhar › Copiar link.",
            "Volte aqui e cole. Se o Tidal bloquear, exporte em CSV e use “Arquivo”.",
        ),
    ),
    FILE(
        "Arquivo", "CSV, M3U ou TXT", "doc.on.doc",
        0xFFC4A0, 0xFF9EC4, null, emptyList(),
    ),
}

sealed interface ImportPhase {
    data object Idle : ImportPhase
    data class Running(val service: String, val message: String) : ImportPhase
    data class Done(val service: String, val items: List<SummaryItem>) : ImportPhase {
        val totalTracks: Int get() = items.sumOf { it.count }
    }
    data class Failed(val message: String) : ImportPhase
}

data class SummaryItem(val name: String, val count: Int, val artworkURL: String)

class ImportCoordinator {
    var phase by mutableStateOf<ImportPhase>(ImportPhase.Idle)
    var importedTracks by mutableIntStateOf(0)
    var importedPlaylists by mutableIntStateOf(0)
    private var activeJob: kotlinx.coroutines.Job? = null

    fun reset() {
        activeJob?.cancel()
        activeJob = null
        phase = ImportPhase.Idle
    }

    suspend fun run(service: String, work: suspend ((String) -> Unit) -> List<ImportService.ImportResult>) {
        if (phase is ImportPhase.Running) return
        activeJob = kotlin.coroutines.coroutineContext[kotlinx.coroutines.Job]
        Haptics.medium()
        phase = ImportPhase.Running(service, "Conectando…")
        try {
            val packs = work { msg -> if (phase is ImportPhase.Running) phase = ImportPhase.Running(service, msg) }
            kotlinx.coroutines.currentCoroutineContext()[kotlinx.coroutines.Job]?.let { if (!it.isActive) return }
            val saved = packs.map { r ->
                val pl = LibraryStore.createPlaylist(r.playlistName, sourceBadge = r.sourceBadge, artworkURL = r.artworkURL, tracks = r.tracks)
                SummaryItem(r.playlistName, r.tracks.size, pl.artworkURL)
            }
            val total = saved.sumOf { it.count }
            importedTracks += total
            importedPlaylists += saved.size
            SoundFX.play(SoundFX.Effect.SUCCESS)
            Haptics.success()
            AppModel.showToast("$total músicas importadas para a sua biblioteca")
            phase = ImportPhase.Done(packs.firstOrNull()?.sourceBadge ?: service, saved)
        } catch (e: kotlinx.coroutines.CancellationException) {
            if (phase is ImportPhase.Running) phase = ImportPhase.Idle
            throw e
        } catch (e: ImportException) {
            SoundFX.play(SoundFX.Effect.ERROR)
            phase = ImportPhase.Failed(e.message ?: "Não foi possível importar.")
        } catch (_: Exception) {
            SoundFX.play(SoundFX.Effect.ERROR)
            phase = ImportPhase.Failed("Não foi possível importar agora. Confira sua conexão e tente novamente.")
        } finally {
            activeJob = null
        }
    }
}

@Composable
fun ImportHubPanel(
    coordinator: ImportCoordinator,
    modifier: Modifier = Modifier,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var sheetKind by remember { mutableStateOf<ImportServiceKind?>(null) }

    val devicePerm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) {
            scope.launch { coordinator.run("Aparelho") { ImportService.importFromDevice(ctx) } }
        } else {
            coordinator.phase = ImportPhase.Failed("Permita o acesso às músicas do aparelho para importar com 1 toque.")
        }
    }

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            coordinator.run("Arquivo") { onProgress ->
                onProgress("Lendo arquivo…")
                val (name, text) = withContext(Dispatchers.IO) {
                    val displayName = queryFileName(ctx, uri) ?: "Playlist.csv"
                    val content = ctx.contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
                    displayName to content
                }
                listOf(ImportService.importFromFile(text, name))
            }
        }
    }

    fun onTap(kind: ImportServiceKind) {
        Haptics.light()
        SoundFX.play(SoundFX.Effect.TAP)
        when (kind) {
            ImportServiceKind.DEVICE -> {
                val p = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
                devicePerm.launch(p)
            }
            ImportServiceKind.FILE -> filePicker.launch(arrayOf("text/*", "text/csv", "application/vnd.ms-excel", "audio/x-mpegurl", "*/*"))
            else -> sheetKind = kind
        }
    }

    AnimatedContent(
        coordinator.phase,
        modifier = modifier.fillMaxWidth(),
        transitionSpec = { fadeIn() togetherWith fadeOut() },
        label = "importPhase",
    ) { p ->
        when (p) {
            ImportPhase.Idle -> ServiceGrid(::onTap)
            is ImportPhase.Running -> ImportProgressCard(p.service, p.message) { coordinator.reset() }
            is ImportPhase.Done -> ImportDoneCard(p) { coordinator.reset() }
            is ImportPhase.Failed -> ImportFailedCard(p.message) { coordinator.reset() }
        }
    }

    sheetKind?.let { kind ->
        ServiceLinkSheet(
            kind = kind,
            onDismiss = { sheetKind = null },
            onSubmit = { raw ->
                sheetKind = null
                val svc = ImportService.serviceNameForLink(raw) ?: kind.title
                scope.launch {
                    coordinator.run(svc) { onProgress -> ImportService.importMultipleURLs(raw, onProgress) }
                }
            },
        )
    }
}

@Composable
private fun ServiceGrid(onTap: (ImportServiceKind) -> Unit) {
    val others = remember { ImportServiceKind.entries.filter { it != ImportServiceKind.DEVICE } }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // Destaque 1-toque: Músicas do celular (equivalente ao card do Apple Music no iPhone)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 76.dp).pressable(0.98f) { onTap(ImportServiceKind.DEVICE) }
                .glass(RoundedCornerShape(22.dp), tint = hex(0xFA2D48)).padding(14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ServiceIcon(ImportServiceKind.DEVICE, 48.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Importar músicas do celular", style = Theme.font(17f, FontWeight.SemiBold, Theme.text))
                Text("Traz todas as músicas salvas neste Android com 1 toque", style = Theme.font(13f, color = Theme.secondary))
            }
            Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(16.dp))
        }

        // Grade 2 colunas: Spotify, YouTube Music, Deezer, Apple Music, Amazon Music, Tidal, Arquivo
        others.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { kind ->
                    Row(
                        Modifier.weight(1f).heightIn(min = 66.dp).pressable(0.96f) { onTap(kind) }
                            .glass(RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        ServiceIcon(kind, 38.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(kind.title, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(kind.tagline, style = Theme.font(11.5f, color = Theme.secondary), maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ServiceIcon(kind: ImportServiceKind, size: Dp) {
    val brush = Brush.linearGradient(listOf(hex(kind.hexA), hex(kind.hexB)))
    Box(
        Modifier.size(size).shadow(8.dp, CircleShape, spotColor = hex(kind.hexB).copy(0.45f))
            .clip(CircleShape).background(brush).border(0.8.dp, Color.White.copy(0.35f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(sf(kind.symbol), null, tint = Color.White, modifier = Modifier.size(size * 0.48f))
    }
}

@Composable
private fun ImportProgressCard(service: String, message: String, onCancel: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().glass(RoundedCornerShape(28.dp)).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        CircularProgressIndicator(color = Theme.rose, strokeWidth = 3.5.dp, modifier = Modifier.size(44.dp))
        Text("Importando de $service…", style = Theme.font(18f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center)
        Text(message, style = Theme.font(13.5f, color = Theme.secondary), textAlign = TextAlign.Center, maxLines = 2)
        GlassButton("Cancelar", height = 44.dp, modifier = Modifier.fillMaxWidth(0.55f)) { onCancel() }
    }
}

@Composable
private fun ImportDoneCard(done: ImportPhase.Done, onMore: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().glass(RoundedCornerShape(28.dp)).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(64.dp).glass(CircleShape, tint = Theme.mint),
            contentAlignment = Alignment.Center,
        ) { Icon(sf("checkmark"), null, tint = Theme.text, modifier = Modifier.size(28.dp)) }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val s = if (done.totalTracks == 1) "" else "s"
            Text("Pronto! ${done.totalTracks} música$s importada$s", style = Theme.font(18f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center)
            val ps = if (done.items.size == 1) "" else "s"
            Text("${done.items.size} playlist$ps (${done.service}) já salva$ps na sua biblioteca", style = Theme.font(13.5f, color = Theme.secondary), textAlign = TextAlign.Center)
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            done.items.take(4).forEach { it ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ArtworkImage(it.artworkURL, Modifier.size(40.dp), 8.dp, icon = "music.note.list")
                    Text(it.name, style = Theme.font(14.5f, FontWeight.Medium, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text("${it.count}", style = Theme.font(13.5f, FontWeight.SemiBold, Theme.secondary))
                }
            }
            if (done.items.size > 4) {
                Text("+ ${done.items.size - 4} playlists", style = Theme.font(12.5f, color = Theme.tertiary))
            }
        }
        GlassButton("Importar de outro lugar", "plus", height = 46.dp) { onMore() }
    }
}

@Composable
private fun ImportFailedCard(message: String, onRetry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().glass(RoundedCornerShape(28.dp), tint = Theme.danger).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(sf("exclamationmark.triangle.fill"), null, tint = Theme.peach, modifier = Modifier.size(30.dp))
        Text(message, style = Theme.font(14.5f, FontWeight.Medium, Theme.text), textAlign = TextAlign.Center)
        GlassButton("Tentar de outro jeito", "arrow.counterclockwise", height = 46.dp) { onRetry() }
    }
}

@Composable
private fun ServiceLinkSheet(kind: ImportServiceKind, onDismiss: () -> Unit, onSubmit: (String) -> Unit) {
    val ctx = LocalContext.current
    val closeKeyboard = rememberKeyboardCloser()
    var manual by remember { mutableStateOf("") }
    var clipLink by remember { mutableStateOf<String?>(null) }

    fun checkClipboard() {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        val txt = cm?.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString().orEmpty()
        clipLink = ImportService.firstLink(txt)
    }

    LaunchedEffect(Unit) { checkClipboard() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { checkClipboard() }

    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = Theme.canvasRaised,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        contentColor = Theme.text,
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().imePadding().keyboardDismissing()
                .padding(horizontal = 22.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ServiceIcon(kind, 68.dp)
            Text("Importar do ${kind.title}", style = Theme.rounded(24f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)

            Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                kind.howTo.forEachIndexed { idx, line ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                        Box(Modifier.size(24.dp).clip(CircleShape).background(Theme.prismDiagonal), contentAlignment = Alignment.Center) {
                            Text("${idx + 1}", style = Theme.font(13f, FontWeight.Bold, Theme.onPrism))
                        }
                        Text(line, style = Theme.font(14.5f, color = Theme.text), modifier = Modifier.weight(1f))
                    }
                }
            }

            if (kind.openUrl != null) {
                GlassButton("Abrir ${kind.title}", "arrow.right", height = 50.dp) {
                    runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(kind.openUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                }
            }

            if (clipLink != null) {
                Column(
                    Modifier.fillMaxWidth().glass(RoundedCornerShape(22.dp), tint = Theme.lavender).padding(14.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text("Você copiou um link. É o da playlist?", style = Theme.font(14f, FontWeight.Medium, Theme.text), textAlign = TextAlign.Center)
                    PrismButton("Colar link e importar", "link", height = 50.dp) {
                        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                        val full = cm?.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString().orEmpty()
                        onSubmit(full.ifBlank { clipLink!! })
                    }
                }
            } else {
                PrismButton("Colar link e importar", "link", height = 50.dp) {
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                    val txt = cm?.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString().orEmpty()
                    if (txt.isNotBlank()) onSubmit(txt)
                    else AppModel.showToast("Copie o link da playlist primeiro")
                }
            }

            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.fillMaxWidth().heightIn(min = 50.dp, max = 120.dp).glass(RoundedCornerShape(22.dp)).padding(horizontal = 16.dp, vertical = 14.dp)) {
                    if (manual.isEmpty()) Text("…ou cole 1 ou vários links aqui (um por linha)", style = Theme.font(14.5f, color = Theme.tertiary))
                    BasicTextField(
                        manual, { manual = it },
                        textStyle = Theme.font(15f, color = Theme.text),
                        cursorBrush = SolidColor(Theme.rose),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { closeKeyboard(); if (manual.isNotBlank()) onSubmit(manual) }),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (manual.isNotBlank()) {
                    PrismButton("Importar do link", "arrow.down.circle", height = 48.dp) {
                        closeKeyboard()
                        onSubmit(manual)
                    }
                }
            }

            Text("Seus dados não saem do celular. O Lume só lê a playlist pública.", style = Theme.font(12f, color = Theme.tertiary), textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 12.dp))
        }
    }
}

private fun queryFileName(ctx: Context, uri: Uri): String? = runCatching {
    ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
        if (c.moveToFirst()) c.getString(0) else null
    }
}.getOrNull()
