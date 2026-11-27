package com.adriano.lumemusic.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusManager
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.ui.theme.Theme

/**
 * Espaços centrais da interface (um único lugar para topo, base e teclado). Mesma regra do iOS:
 * o conteúdo rolável termina ACIMA da barra de abas + mini player + barra de navegação + folga.
 */
object Chrome {
    /** Altura da barra de abas flutuante (vidro). */
    val tabBarHeight = 62.dp
    /** Folga abaixo da barra de abas (acima da barra de navegação). */
    val tabBarBottomPad = 6.dp
    /** Mini player + espaço entre ele e a barra de abas. */
    val miniPlayerBlock = 60.dp + 10.dp
    /** Folga final para o último item subir bem acima da barra e do mini player. */
    val breathing = 32.dp
    /** Altura mínima do cabeçalho padrão das telas de detalhe. */
    val detailHeaderMin = 56.dp
    /** Alvo de toque mínimo. */
    val minTouch = 48.dp

    /** Espaço inferior de conteúdo: barra de abas + mini player (se houver) + navigationBars + folga. */
    fun bottomInset(navigationBottom: Dp, hasTrack: Boolean): Dp =
        navigationBottom + tabBarBottomPad + tabBarHeight + (if (hasTrack) miniPlayerBlock else 0.dp) + breathing
}

/** Altura atual da barra de navegação do sistema (em dp). */
@Composable
fun navigationBarBottomDp(): Dp {
    val density = LocalDensity.current
    val insets = WindowInsets.navigationBars
    return remember(density, insets) { derivedStateOf { with(density) { insets.getBottom(density).toDp() } } }.value
}

/** `true` enquanto o teclado está aberto (só recompõe quando muda de aberto/fechado, não a cada quadro da animação). */
@Composable
fun rememberImeVisible(): Boolean {
    val density = LocalDensity.current
    val insets = WindowInsets.ime
    val visible by remember(density, insets) { derivedStateOf { insets.getBottom(density) > 0 } }
    return visible
}

/** Fecha o teclado E tira o foco do campo (mesmo comportamento em qualquer tela/pop-up). */
@Composable
fun rememberKeyboardCloser(): () -> Unit {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    return remember(keyboard, focus) { { keyboard?.hide(); focus.clearFocus() } }
}

private class HideKeyboardOnScroll(private val isOpen: () -> Boolean, private val close: () -> Unit) : NestedScrollConnection {
    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (source == NestedScrollSource.UserInput && available.y != 0f && isOpen()) close()
        return Offset.Zero
    }
}

/**
 * Teclado sempre dispensável: tocar numa área vazia fecha (os botões e campos consomem o próprio toque, então nada é roubado)
 * e começar a rolar uma lista também fecha. Aplicar na raiz da tela e no conteúdo de cada pop-up/sheet.
 */
fun Modifier.keyboardDismissing(): Modifier = composed {
    val close = rememberKeyboardCloser()
    val density = LocalDensity.current
    val ime = WindowInsets.ime
    val closeNow by rememberUpdatedState(close)
    val connection = remember { HideKeyboardOnScroll({ ime.getBottom(density) > 0 }, { closeNow() }) }
    this.nestedScroll(connection).pointerInput(Unit) { detectTapGestures(onTap = { closeNow() }) }
}

/** Telas cheias por cima de outras (Cover Flow etc.): toques em áreas vazias não atravessam para o app que está atrás. */
fun Modifier.blockTouchesBehind(): Modifier = pointerInput(Unit) { detectTapGestures { } }

/** Botão "OK" que aparece enquanto o teclado está aberto (campos de código de caixinhas, campos longos). */
@Composable
fun KeyboardOkButton(modifier: Modifier = Modifier, onOk: () -> Unit = {}) {
    val visible = rememberImeVisible()
    val close = rememberKeyboardCloser()
    AnimatedVisibility(visible, modifier = modifier, enter = fadeIn(), exit = fadeOut()) {
        Box(
            Modifier.width(120.dp).height(Chrome.minTouch).pressable(0.94f) { onOk(); close() }
                .glass(androidx.compose.foundation.shape.RoundedCornerShape(50)).padding(horizontal = 20.dp),
            contentAlignment = Alignment.Center,
        ) { Text("OK", style = Theme.font(16f, FontWeight.Bold, Theme.accent)) }
    }
}
