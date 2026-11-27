package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.heightIn
import com.adriano.lumemusic.ui.rememberImeVisible
import com.adriano.lumemusic.ui.keyboardDismissing
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import com.adriano.lumemusic.ui.KeyboardOkButton
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.access.AccessInfo
import com.adriano.lumemusic.access.AccessService
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.ActivateResult
import com.adriano.lumemusic.ui.LumeWordmark
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.UpgradeModel
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.launch

/** Caixas do código (6 caracteres) + botão. Reutilizada no portão e no onboarding. */
@Composable
fun AccessCodeEntry(
    title: String, subtitle: String?, buttonTitle: String = "Ativar", prefill: String? = null,
    extra: (@Composable () -> Unit)? = null, onActivated: (AccessInfo) -> Unit,
) {
    var raw by remember { mutableStateOf(prefill ?: "") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    val closeKeyboard = rememberKeyboardCloser()
    val code = AccessService.normalizeCode(raw).take(6)

    fun submit() {
        if (busy) return
        if (!AccessService.isValidCodeFormat(code)) { error = "O código tem 6 letras e números."; return }
        busy = true; error = null
        scope.launch {
            when (val r = Access.service.activate(code, android.os.Build.MODEL)) {
                is ActivateResult.Success -> onActivated(r.info)
                is ActivateResult.Failure -> error = r.message
            }
            busy = false
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(title, style = Theme.font(26f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
        if (subtitle != null) Text(subtitle, style = Theme.font(15f, color = Theme.secondary), textAlign = TextAlign.Center)
        Box(Modifier.fillMaxWidth().clickable(indication = null, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }) { focus.requestFocus() }) {
            BasicTextField(
                raw, { raw = AccessService.normalizeCode(it).filter { c -> c.isLetterOrDigit() }.take(6); error = null },
                modifier = Modifier.focusRequester(focus).size(1.dp), singleLine = true, cursorBrush = SolidColor(Color.Transparent),
                textStyle = Theme.font(1f, color = Color.Transparent),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { closeKeyboard(); submit() }),
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (i in 0 until 6) {
                    val ch = code.getOrNull(i)?.toString() ?: ""
                    val active = i == code.length.coerceAtMost(5)
                    Box(
                        Modifier.weight(1f).height(60.dp).glass(RoundedCornerShape(16.dp))
                            .then(if (active) Modifier.border(1.5.dp, Theme.prismDiagonal, RoundedCornerShape(16.dp)) else Modifier),
                        contentAlignment = Alignment.Center,
                    ) { Text(ch, style = Theme.rounded(26f, FontWeight.Bold, Theme.text)) }
                }
            }
        }
        // Botão OK sempre visível enquanto o teclado está aberto: envia se o código está completo, senão só fecha o teclado.
        KeyboardOkButton { if (code.length == 6) submit() }
        error?.let { Text(it, style = Theme.font(14f, FontWeight.Medium, Theme.danger), textAlign = TextAlign.Center) }
        if (busy) CircularProgressIndicator(Modifier.size(26.dp), color = Theme.rose, strokeWidth = 2.5.dp)
        else PrismButton(buttonTitle) { submit() }
        extra?.invoke()
    }
}

/** Botões extras do portão e do onboarding: Restaurar compra (código salvo), Comprar vitalício e Já sou vitalício. */
@Composable
fun AccessGateExtras(prefill: String?) {
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (prefill != null) {
            if (busy) CircularProgressIndicator(Modifier.size(24.dp), color = Theme.rose, strokeWidth = 2.5.dp)
            else GlassButton("Restaurar compra", "arrow.counterclockwise") {
                busy = true; error = null
                scope.launch {
                    val r = com.adriano.lumemusic.access.Purchase.service.restore(prefill)
                    if (r is ActivateResult.Failure) error = r.message
                    busy = false
                }
            }
            error?.let { Text(it, style = Theme.font(13.5f, FontWeight.Medium, Theme.danger), textAlign = TextAlign.Center) }
        }
        GlassButton("Comprar vitalício · ${UpgradeModel.shortPrice}", "sparkles") { UpgradeModel.openUpgrade() }
        Box(Modifier.heightIn(min = 48.dp).pressable(0.96f) { UpgradeModel.showRecover = true }.padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
            Text("Já sou vitalício", style = Theme.font(15f, FontWeight.SemiBold, Theme.accent))
        }
    }
}

@Composable
fun AccessSuccessView(info: AccessInfo, buttonTitle: String, onContinue: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(96.dp).glass(androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) {
            Icon(sf("checkmark.seal.fill"), null, tint = Theme.ok, modifier = Modifier.size(52.dp))
        }
        Text(info.successMessage(), style = Theme.font(22f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
        info.note?.takeIf { it.isNotBlank() }?.let { Text(it, style = Theme.font(15f, color = Theme.secondary), textAlign = TextAlign.Center) }
        PrismButton(buttonTitle) { onContinue() }
    }
}

/** Portão: aparece sobre tudo quando o painel está ligado e não há acesso válido. */
@Composable
fun AccessGateScreen() {
    val state by Access.service.state.collectAsState()
    var justActivated by remember { mutableStateOf<AccessInfo?>(null) }
    val locked = (state as? AccessState.Locked)
        ?: if (UpgradeModel.debugTrialUsed) AccessState.Locked("Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício.") else null
    if (locked == null && justActivated == null) return
    val scroll = androidx.compose.foundation.rememberScrollState()
    val imeOpen = rememberImeVisible()
    // Com o teclado aberto, rola até o fim: caixinhas, OK e Ativar continuam à vista.
    androidx.compose.runtime.LaunchedEffect(imeOpen) { if (imeOpen) { kotlinx.coroutines.delay(320); scroll.animateScrollTo(scroll.maxValue) } }
    // keyboardDismissing também impede que toques atravessem o portão para o app que está atrás.
    Box(Modifier.fillMaxSize().background(Theme.canvas).keyboardDismissing().statusBarsPadding().navigationBarsPadding().imePadding(), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.radialGradient(listOf(Theme.lavender.copy(0.25f), Color.Transparent), radius = 1200f)))
        Column(Modifier.fillMaxWidth().verticalScroll(scroll).padding(vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
            LumeWordmark(34f)
            AnimatedContent(justActivated, transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }, label = "gate") { ja ->
                if (ja != null) AccessSuccessView(ja, "Entrar na Lume") { justActivated = null; UpgradeModel.onActivated(ja) }
                else AccessCodeEntry(
                    title = when {
                        UpgradeModel.debugTrialUsed || Access.service.trialUsedMessage() != null -> "Seu teste grátis terminou"
                        locked?.message == null -> "Digite seu código de acesso"
                        else -> "Precisamos do seu código"
                    },
                    subtitle = if (UpgradeModel.debugTrialUsed || Access.service.trialUsedMessage() != null)
                        "Garanta a Lume para sempre com o Vitalício. Se você recebeu um código, digite-o abaixo." else locked?.message, prefill = locked?.prefillCode,
                    extra = { AccessGateExtras(locked?.prefillCode) },
                ) { justActivated = it }
            }
            Text("Sua biblioteca continua guardada neste aparelho.", style = Theme.font(13f, FontWeight.Medium, Theme.secondary))
        }
    }
}

/** Cartão "Seu acesso" dos Ajustes (contrato v2/v2.1): grátis com dias restantes ou vitalício com código, transferência e PIN. */
@Composable
fun AccessStatusCard() {
    val state by Access.service.state.collectAsState()
    val info = (state as? AccessState.Active)?.info ?: return
    val ctx = androidx.compose.ui.platform.LocalContext.current
    var copied by remember { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(copied) { if (copied) { kotlinx.coroutines.delay(1500); copied = false } }
    val days = info.daysLeft(System.currentTimeMillis())
    val status = when {
        info.lifetime -> "Vitalício"
        days != null -> "Grátis · " + if (days <= 0) "vence hoje" else if (days == 1) "falta 1 dia" else "faltam $days dias"
        else -> "Ativo"
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).glass(RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(sf("checkmark.seal.fill"), null, tint = Theme.ok, modifier = Modifier.size(30.dp))
            Column(Modifier.weight(1f)) {
                Text("Seu acesso", style = Theme.font(16f, FontWeight.SemiBold, Theme.text))
                Text(status, style = Theme.font(13.5f, color = Theme.secondary))
            }
        }
        if (info.lifetime) {
            val rev = UpgradeModel.revealed
            androidx.compose.runtime.DisposableEffect(Unit) { onDispose { UpgradeModel.revealed = null } }
            if (rev == null) {
                Row(
                    Modifier.fillMaxWidth().height(52.dp).glass(RoundedCornerShape(16.dp)).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text("Código  ••••••", style = Theme.rounded(20f, FontWeight.Bold, Theme.text), modifier = Modifier.weight(1f))
                }
                GlassButton("Ver meu código", "lock.fill") { UpgradeModel.showReveal = true }
            } else {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).pressable(0.98f) { com.adriano.lumemusic.ui.screens.copyToClipboard(ctx, rev.first, sensitive = true); copied = true }.glass(RoundedCornerShape(16.dp)).padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(rev.first, style = Theme.rounded(22f, FontWeight.Bold, Theme.text), modifier = Modifier.weight(1f))
                    Text(if (copied) "Copiado ✓" else "Toque para copiar", style = Theme.font(12.5f, FontWeight.Medium, Theme.secondary))
                }
                (rev.second ?: info.purchase)?.let { Text("Pedido $it", style = Theme.font(15f, FontWeight.SemiBold, Theme.text)) }
            }
            Text("Guarde este código: com ele você recupera a Lume em outro celular ou se reinstalar", style = Theme.font(13f, color = Theme.secondary))
            GlassButton("Transferir para outro aparelho", "arrow.left.arrow.right") { UpgradeModel.showTransfer = true }
            GlassButton("Trocar PIN", "lock.fill") { UpgradeModel.pinMode = "change" }
            GlassButton("Restaurar compra", "arrow.counterclockwise") { UpgradeModel.showRestore = true }
        } else {
            PrismButton("Fazer upgrade para o Vitalício · ${UpgradeModel.shortPrice}", "sparkles") { UpgradeModel.openUpgrade() }
            GlassButton("Tenho um código", "key.fill") { UpgradeModel.showCodeEntry = true }
            GlassButton("Já sou vitalício", "arrow.left.arrow.right") { UpgradeModel.showRecover = true }
            GlassButton("Restaurar compra", "arrow.counterclockwise") { UpgradeModel.showRestore = true }
        }
    }
}
