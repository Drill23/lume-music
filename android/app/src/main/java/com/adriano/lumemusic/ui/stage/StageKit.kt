package com.adriano.lumemusic.ui.stage

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf

// Cores do "chrome" dos palcos (o Tocando agora é sempre escuro, como no iOS com malha da capa).
internal val StageText = Color.White
internal val StageSecondary = Color.White.copy(alpha = 0.62f)

private fun sp(v: Float, kind: TextUnitType = TextUnitType.Sp) = TextUnit(v, kind)

// ====================================================================== Seletor de palco

/**
 * Pílula de vidro com 5 alvos de 44 dp (ícone + rótulo) e um indicador que desliza entre eles.
 * Larguras fixas: nada muda de lugar sob o dedo quando você troca de palco. (StageSwitcher do StageKit.swift.)
 */
@Composable
fun StageSwitcher(selection: PlayerSurfaceTab, onSelect: (PlayerSurfaceTab) -> Unit, modifier: Modifier = Modifier) {
    val tabs = PlayerSurfaceTab.entries
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        val cell = (maxWidth - 8.dp - 8.dp) / tabs.size   // padding 4+4 e 4 vãos de 2
        val idx = tabs.indexOf(selection)
        val x by animateDpAsState((cell + 2.dp) * idx, spring(0.84f, 220f), label = "stageInd")
        Box(Modifier.fillMaxWidth().height(52.dp).glass(RoundedCornerShape(50)).padding(4.dp)) {
            Box(
                Modifier.offset(x = x).size(cell, 44.dp).clip(RoundedCornerShape(50)).background(Theme.prismDiagonal)
                    .border(0.8.dp, Color.White.copy(0.5f), RoundedCornerShape(50)),
            )
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                for (t in tabs) {
                    val active = selection == t
                    Row(
                        Modifier.width(cell).height(44.dp).clip(RoundedCornerShape(50)).pressable(0.94f) { if (!active) { Haptics.selection(); onSelect(t) } },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
                    ) {
                        val c = if (active) Theme.onPrism else StageSecondary
                        Icon(sf(t.icon), null, tint = c, modifier = Modifier.size(15.dp))
                        Text(t.raw, style = Theme.font(11.5f, FontWeight.SemiBold, c), maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp))
                    }
                }
            }
        }
    }
}

// ====================================================================== Peças dos painéis (alvos >= 44 dp)

@Composable
fun StageSectionHeader(title: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Theme.font(11f, FontWeight.ExtraBold, StageSecondary, letterSpacing = sp(0.9f)))
        Box(Modifier.weight(1f).widthIn(min = 8.dp))
        if (trailing != null) Text(trailing, style = Theme.font(12f, FontWeight.SemiBold, StageText), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Segmentado de 44 dp com indicador. */
@Composable
fun <T> StageSegmented(items: List<Pair<T, String>>, selection: T, onSelect: (T) -> Unit) {
    val shape = RoundedCornerShape(50)
    BoxWithConstraints(Modifier.fillMaxWidth().clip(shape).background(Color.White.copy(0.07f)).border(0.6.dp, Color.White.copy(0.12f), shape).padding(3.dp)) {
        val cell = (maxWidth - 2.dp * (items.size - 1)) / items.size
        val idx = items.indexOfFirst { it.first == selection }.coerceAtLeast(0)
        val x by animateDpAsState((cell + 2.dp) * idx, spring(0.8f, 380f), label = "seg")
        Box(Modifier.offset(x = x).size(cell, 44.dp).clip(shape).background(Theme.prismDiagonal))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for ((v, title) in items) {
                val active = v == selection
                Box(Modifier.width(cell).height(44.dp).clip(shape).pressable(0.94f) { if (!active) { Haptics.selection(); onSelect(v) } }, contentAlignment = Alignment.Center) {
                    Text(title, style = Theme.font(13f, FontWeight.SemiBold, if (active) Theme.onPrism else StageText), maxLines = 1)
                }
            }
        }
    }
}

/** Bolinha de amostra (44 dp) com anel que marca a opção ativa. */
@Composable
fun StageSwatch(selected: Boolean, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, fill: @Composable () -> Unit) {
    Box(modifier.size(48.dp).pressable(0.94f) { if (!selected) { Haptics.selection(); onClick() } }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(34.dp).clip(CircleShape).border(0.8.dp, Color.White.copy(0.35f), CircleShape)) { fill() }
        if (selected) {
            Box(Modifier.size(44.dp).border(2.5.dp, Theme.prismDiagonal, CircleShape))
            Icon(sf("checkmark"), label, tint = Color.White, modifier = Modifier.size(15.dp))
        }
    }
}

/** Linha de opção de 48 dp (amostra + título + subtítulo + check). */
@Composable
fun StageOptionRow(title: String, subtitle: String?, selected: Boolean, onClick: () -> Unit, leading: @Composable () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val fg = if (selected) Theme.onPrism else StageText
    Row(
        Modifier.fillMaxWidth().height(48.dp).clip(shape).background(if (selected) Theme.prismDiagonal else androidx.compose.ui.graphics.SolidColor(Color.White.copy(0.07f)), shape)
            .pressable(0.96f) { if (!selected) { Haptics.selection(); onClick() } }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(28.dp)) { leading() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(14f, if (selected) FontWeight.Bold else FontWeight.SemiBold, fg), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = Theme.font(11f, color = fg.copy(alpha = 0.7f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (selected) Icon(sf("checkmark"), null, tint = fg, modifier = Modifier.size(15.dp))
    }
}

/** Botão de vidro de 44 dp para as docas dos palcos. */
@Composable
fun StageDockButton(icon: String, title: String?, tint: Color?, minWidth: Int = 44, desc: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier.defaultMinSize(minWidth = minWidth.dp, minHeight = 44.dp).glass(shape, tint).pressable(0.94f) { Haptics.light(); onClick() }
            .padding(horizontal = if (title == null) 0.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        Icon(sf(icon), desc, tint = StageText, modifier = Modifier.size(17.dp))
        if (title != null) Text(title, style = Theme.font(13f, FontWeight.SemiBold, StageText), maxLines = 1, modifier = Modifier.padding(start = 6.dp))
    }
}

// ====================================================================== Botão de estilos que se expande em painel de vidro

/**
 * Botão (44 dp) que abre um painel de acabamentos no canto inferior direito do palco. O painel cresce a partir do
 * canto do botão, o toque fora dele fecha, e ele nunca é cortado: ocupa só a área do palco e rola quando não cabe.
 * (StageStyleOrb do StageKit.swift: largura 304, padding 10, cantos 30, margens 14/8.)
 */
@Composable
fun BoxScope.StageStyleOrb(
    icon: String = "paintpalette.fill",
    desc: String = "Estilos visuais",
    title: String? = null,
    top: Boolean = false,
    content: @Composable (dismiss: () -> Unit) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val origin = TransformOrigin(1f, if (top) 0f else 1f)
    if (expanded) Box(Modifier.matchParentSizeCompat().clickable(MutableInteractionSource(), null) { expanded = false })
    BoxWithConstraints(Modifier.matchParentSizeCompat()) {
        val maxH = maxHeight - 16.dp
        Box(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 8.dp), contentAlignment = if (top) Alignment.TopEnd else Alignment.BottomEnd) {
            AnimatedVisibility(
                visible = !expanded,
                enter = scaleIn(spring(0.82f, 320f), 0.6f, origin) + fadeIn(),
                exit = scaleOut(spring(0.82f, 320f), 0.6f, origin) + fadeOut(),
            ) {
                Box(
                    Modifier.defaultMinSize(44.dp, 44.dp).glass(RoundedCornerShape(50)).pressable(0.94f) { Haptics.selection(); expanded = true }
                        .padding(horizontal = if (title == null) 0.dp else 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Icon(sf(icon), desc, tint = StageText, modifier = Modifier.size(17.dp))
                        if (title != null) Text(title, style = Theme.font(13f, FontWeight.SemiBold, StageText), maxLines = 1)
                    }
                }
            }
            AnimatedVisibility(
                visible = expanded,
                enter = scaleIn(spring(0.82f, 320f), 0.3f, origin) + fadeIn(),
                exit = scaleOut(spring(0.82f, 320f), 0.3f, origin) + fadeOut(),
            ) {
                val shape = RoundedCornerShape(30.dp)
                Column(Modifier.width(304.dp).shadow(16.dp, shape, ambientColor = Color.Black.copy(0.28f), spotColor = Color.Black.copy(0.28f)).glass(shape, blur = true).padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth().padding(start = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(sf(icon), null, tint = StageText, modifier = Modifier.size(16.dp))
                        Text(title ?: "Estilos", style = Theme.font(14f, FontWeight.Bold, StageText), modifier = Modifier.padding(start = 6.dp).weight(1f))
                        Box(Modifier.size(44.dp).clip(CircleShape).background(Color.White.copy(0.10f)).pressable(0.94f) { expanded = false }.semanticsClose(), contentAlignment = Alignment.Center) {
                            Icon(sf("xmark"), "Fechar", tint = StageText, modifier = Modifier.size(15.dp))
                        }
                    }
                    Column(Modifier.fillMaxWidth().heightIn(max = (maxH - 70.dp).coerceAtLeast(120.dp)).verticalScroll(rememberScrollState())) {
                        content { expanded = false }
                    }
                }
            }
        }
    }
}

/** Cinza (UIColor(white:)). */
internal fun G(v: Float, a: Float = 1f) = Color(v, v, v, a)

private fun Modifier.semanticsClose(): Modifier = this

/** Ocupa toda a área do palco (o BoxScope do chamador é um Box que preenche o palco). */
private fun Modifier.matchParentSizeCompat(): Modifier = this.fillMaxSize()
