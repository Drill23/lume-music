package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.rememberImeVisible
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import com.adriano.lumemusic.ui.keyboardDismissing
import com.adriano.lumemusic.ui.KeyboardOkButton
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessService
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.ActivateResult
import com.adriano.lumemusic.access.Purchase
import com.adriano.lumemusic.access.PurchaseResult
import com.adriano.lumemusic.access.PurchaseOrder
import com.adriano.lumemusic.access.isValidPin
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.PrismIcon
import com.adriano.lumemusic.ui.QrMatrix
import com.adriano.lumemusic.ui.UpgradeModel
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import com.adriano.lumemusic.update.UpdateController
import com.adriano.lumemusic.update.UpdatePhase
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.sin

// ============================================================ Base: overlay de vidro

fun copyToClipboard(ctx: Context, text: String, sensitive: Boolean = false) {
    try {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Lume", text)
        if (sensitive && android.os.Build.VERSION.SDK_INT >= 33) clip.description.extras = android.os.PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
        cm.setPrimaryClip(clip)
    } catch (_: Exception) {}
}

/**
 * Pop-up/sheet de vidro sobre tudo: fundo escurecido, painel com blur do Haze (Liquid Glass) que entra com mola (escala + fade).
 * [onDismiss] nulo = obrigatório (o botão voltar não fecha). [sheet] ancora embaixo em vez de centralizar.
 */
@Composable
fun GlassOverlay(onDismiss: (() -> Unit)?, sheet: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val appear = remember { MutableTransitionState(false).apply { targetState = true } }
    val scrim by animateFloatAsState(if (appear.targetState) 0.58f else 0f, tween(260), label = "scrim")
    BackHandler { onDismiss?.invoke() }
    val closeKeyboard = rememberKeyboardCloser()
    val imeOpen = rememberImeVisible()
    val scroll = rememberScrollState()
    // Com o teclado aberto o painel encolhe: rola até o fim para o campo e o botão principal continuarem visíveis.
    LaunchedEffect(imeOpen) { if (imeOpen) { delay(320); scroll.animateScrollTo(scroll.maxValue) } }
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = scrim)).clickable(remember { MutableInteractionSource() }, null) { if (imeOpen) closeKeyboard() else onDismiss?.invoke() },
        contentAlignment = if (sheet) Alignment.BottomCenter else Alignment.Center,
    ) {
        AnimatedVisibility(
            appear,
            enter = if (sheet) slideInVertically(spring(0.86f, 380f)) { it / 2 } + fadeIn(tween(200)) else scaleIn(spring(0.72f, 420f), 0.86f) + fadeIn(tween(220)),
        ) {
            val shape = RoundedCornerShape(30.dp)
            Column(
                Modifier.statusBarsPadding().navigationBarsPadding().imePadding().padding(horizontal = 16.dp, vertical = 14.dp)
                    .widthIn(max = 440.dp).fillMaxWidth()
                    .shadow(24.dp, shape, ambientColor = Color.Black.copy(0.35f), spotColor = Color.Black.copy(0.35f))
                    .glass(shape, blur = true).background(Theme.canvasRaised.copy(alpha = 0.40f))
                    .keyboardDismissing()
                    .verticalScroll(scroll).padding(horizontal = 22.dp, vertical = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
                content = content,
            )
        }
        // (o botão fechar fica dentro do conteúdo: ver CloseRow)
    }
}

@Composable
private fun CloseRow(onClose: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Box(Modifier.size(48.dp).pressable(0.9f) { Haptics.light(); onClose() }.glass(CircleShape), contentAlignment = Alignment.Center) {
            Icon(sf("xmark"), "Fechar", tint = Theme.text, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun HeaderIcon(icon: String) {
    Box(Modifier.size(72.dp).glass(CircleShape), contentAlignment = Alignment.Center) { PrismIcon(icon, 36.dp) }
}

@Composable
private fun Title(text: String) = Text(text, style = Theme.font(24f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)

@Composable
private fun Body(text: String, color: Color = Theme.secondary, size: Float = 15f) =
    Text(text, style = Theme.font(size, color = color), textAlign = TextAlign.Center)

@Composable
private fun ErrorText(text: String?) {
    if (text != null) Text(text, style = Theme.font(14f, FontWeight.Medium, Theme.danger), textAlign = TextAlign.Center)
}

/** Botão de cópia com confirmação "Copiado ✓" por 1,5 s. */
@Composable
private fun CopyButton(title: String, text: String, prism: Boolean = false, sensitive: Boolean = false) {
    val ctx = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1500); copied = false } }
    val label = if (copied) "Copiado ✓" else title
    if (prism) PrismButton(label, "doc.on.doc") { copyToClipboard(ctx, text, sensitive); copied = true }
    else GlassButton(label, "doc.on.doc") { copyToClipboard(ctx, text, sensitive); copied = true }
}

@Composable
private fun Busy() = CircularProgressIndicator(Modifier.size(26.dp), color = Theme.rose, strokeWidth = 2.5.dp)

// ============================================================ Caixas de código (código, PIN, transferência)

@Composable
fun CodeBoxes(
    value: String, count: Int, onChange: (String) -> Unit, hidden: Boolean = false, numeric: Boolean = false,
    autoFocus: Boolean = false, onDone: () -> Unit = {}, boxHeight: Dp = 56.dp, stripPrefix: String? = null,
) {
    val focus = remember { FocusRequester() }
    val closeKeyboard = rememberKeyboardCloser()
    LaunchedEffect(autoFocus) { if (autoFocus) { delay(350); try { focus.requestFocus() } catch (_: Exception) {} } }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
    Box(Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, null) { focus.requestFocus() }) {
        BasicTextField(
            value, { v ->
                onChange(
                    if (numeric) v.filter { it in '0'..'9' }.take(count)
                    else {
                        var n = AccessService.normalizeCode(v).filter { it.isLetterOrDigit() }
                        if (stripPrefix != null && n.startsWith(stripPrefix) && n.length > count) n = n.removePrefix(stripPrefix)
                        n.take(count)
                    },
                )
            },
            modifier = Modifier.focusRequester(focus).size(1.dp), singleLine = true, cursorBrush = SolidColor(Color.Transparent),
            textStyle = Theme.font(1f, color = Color.Transparent),
            keyboardOptions = KeyboardOptions(
                capitalization = if (numeric) KeyboardCapitalization.None else KeyboardCapitalization.Characters,
                keyboardType = if (numeric) KeyboardType.NumberPassword else KeyboardType.Ascii, imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { onDone(); closeKeyboard() }),
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (count > 6) 5.dp else 8.dp)) {
            for (i in 0 until count) {
                val ch = value.getOrNull(i)
                val active = i == value.length.coerceAtMost(count - 1)
                Box(
                    Modifier.weight(1f).height(boxHeight).glass(RoundedCornerShape(14.dp))
                        .then(if (active) Modifier.border(1.5.dp, Theme.prismDiagonal, RoundedCornerShape(14.dp)) else Modifier),
                    contentAlignment = Alignment.Center,
                ) { Text(if (ch == null) "" else if (hidden) "●" else ch.toString(), style = Theme.rounded(if (count > 6) 22f else 26f, FontWeight.Bold, Theme.text)) }
            }
        }
    }
    // Botão OK sempre visível enquanto o teclado está aberto: envia se o código está completo, senão só fecha o teclado.
    KeyboardOkButton { if (value.length >= count) onDone() }
    }
}

/** Código só para ler (caixas preenchidas). */
@Composable
private fun CodeDisplay(code: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until 6) Box(Modifier.weight(1f).height(58.dp).glass(RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
            Text(code.getOrNull(i)?.toString() ?: "", style = Theme.rounded(26f, FontWeight.Bold, Theme.text))
        }
    }
}

// ============================================================ QR Code (gerado no aparelho)

@Composable
fun QrCode(text: String, size: Dp = 224.dp) {
    val matrix = remember(text) { QrMatrix.build(text) }
    Canvas(Modifier.size(size).clip(RoundedCornerShape(18.dp)).background(Color.White)) {
        val m = matrix ?: return@Canvas
        val n = m.size
        val quiet = 3
        val total = n + quiet * 2
        val module = floor(this.size.minDimension / total).coerceAtLeast(1f)   // módulos de pixels inteiros: borda nítida
        val off = Offset((this.size.width - module * total) / 2f, (this.size.height - module * total) / 2f)
        for (y in 0 until n) for (x in 0 until n) if (m[y][x]) {
            drawRect(Color.Black, Offset(off.x + (x + quiet) * module, off.y + (y + quiet) * module), Size(module, module))
        }
    }
}

// ============================================================ Boas-vindas

@Composable
fun WelcomeDialog(days: Int, reminder: Boolean) {
    val dayText = if (days == 1) "1 dia" else "$days dias"
    GlassOverlay(onDismiss = { UpgradeModel.dismissWelcome() }) {
        HeaderIcon("sparkles")
        Title(if (reminder) (if (days <= 1) "Seu acesso grátis termina amanhã" else "Faltam $dayText do seu acesso") else "Bem-vindo à Lume ✨")
        Text(
            if (reminder) "Garanta o vitalício e continue ouvindo sem limites." else "Você tem $dayText grátis para curtir tudo.",
            style = Theme.font(17f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center,
        )
        Body(if (reminder) "É um pagamento único: sem mensalidade e com todas as atualizações." else "Músicas, letras, ondas, vinil e K7 — sem pressa. Se gostar, o vitalício é um pagamento único.")
        Spacer(Modifier.height(2.dp))
        PrismButton("Começar a ouvir") { UpgradeModel.dismissWelcome() }
        GlassButton("Quero o vitalício · ${UpgradeModel.shortPrice}") { UpgradeModel.openUpgrade() }
    }
}

// ============================================================ Tela de upgrade

@Composable
fun UpgradeSheet() {
    val ctx = LocalContext.current
    val order = UpgradeModel.order
    val close = { UpgradeModel.closeUpgrade() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { if (UpgradeModel.order == null || UpgradeModel.loadError != null) UpgradeModel.loadOrder() }
    GlassOverlay(onDismiss = close, sheet = true) {
        CloseRow(close)
        HeaderIcon("sparkles")
        Title("Lume Vitalício")
        Text(order?.amountText?.ifBlank { null } ?: UpgradeModel.priceText, style = Theme.rounded(40f, FontWeight.Bold, Theme.text))
        Body("pagamento único", Theme.tertiary, 13f)
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (b in listOf("Para sempre no seu aparelho", "Todas as atualizações", "Sem mensalidade")) {
                Row(Modifier.height(30.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PrismIcon("checkmark", 18.dp)
                    Text(b, style = Theme.font(16f, FontWeight.Medium, Theme.text))
                }
            }
        }
        val url = order?.checkoutUrl
        if (url != null) PrismButton("Pagar com Pix ou cartão") {
            try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
        }
        when {
            UpgradeModel.loading && order == null -> { Spacer(Modifier.height(6.dp)); Busy(); Body("Preparando seu Pix…") }
            order?.pix != null -> PixSection(order, hasCheckout = url != null)
            else -> {
                ErrorText(UpgradeModel.loadError ?: "Não foi possível preparar o pagamento agora.")
                GlassButton("Tentar de novo", "arrow.clockwise") { Haptics.light(); scope.launch { UpgradeModel.loadOrder() } }
            }
        }
    }
}

@Composable
private fun PixSection(order: PurchaseOrder, hasCheckout: Boolean) {
    val pix = order.pix ?: return
    val automatic = pix.automatic
    Text(if (hasCheckout) "Ou pague com Pix" else "Pague com Pix", style = Theme.font(18f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
    QrCode(pix.copiaECola)
    CopyButton("Copiar Pix copia e cola", pix.copiaECola, prism = !hasCheckout)
    if (automatic) {
        WaitingIndicator()
        Body("Assim que o Pix cair, seu acesso vitalício é liberado sozinho — pode deixar esta tela aberta", Theme.secondary, 14.5f)
    } else {
        val key = pix.key
        if (key != null) CopyButton("Copiar chave", key)
        if (UpgradeModel.claimState == "review") {
            WaitingIndicator()
            Text("Aguardando confirmação", style = Theme.font(16f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center)
            Body(UpgradeModel.statusMessage ?: "Recebemos seu aviso. Assim que o pagamento for confirmado, seu código aparece aqui.", Theme.secondary, 14f)
        } else if (UpgradeModel.claimState == "sending") Busy()
        else GlassButton("Já paguei", "checkmark") { UpgradeModel.claim() }
    }
    ErrorText(UpgradeModel.loadError)
    UpgradeModel.statusMessage?.takeIf { UpgradeModel.claimState != "review" }?.let { Body(it, Theme.secondary, 13.5f) }
}

/** Três pontos pulsando em sequência (espera pelo Pix). */
@Composable
private fun WaitingIndicator() {
    val t = rememberInfiniteTransition(label = "wait")
    val phase by t.animateFloat(0f, 1f, infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Restart), label = "p")
    Row(Modifier.height(24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        for (i in 0 until 3) {
            val s = 0.55f + 0.45f * (0.5f + 0.5f * sin((phase * 2f - i * 0.33f) * Math.PI.toFloat()))
            Box(Modifier.size(10.dp).graphicsLayer { scaleX = s; scaleY = s; alpha = s }.background(Theme.prismDiagonal, CircleShape))
        }
    }
}


// ============================================================ Pagamento confirmado

@Composable
fun PaidDialog() {
    val code = UpgradeModel.paidCode ?: return
    val phase = UpgradeModel.paidPhase
    GlassOverlay(onDismiss = null) {
        Confetti()
        HeaderIcon("checkmark.seal.fill")
        Title("Pagamento confirmado!")
        when (phase) {
            "done" -> {
                Text("Acesso vitalício ✨ Obrigado por comprar!", style = Theme.font(17f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center)
                Body("Seu código vitalício:")
                CodeDisplay(code)
                UpgradeModel.paidOrder?.let { Text("Pedido $it", style = Theme.rounded(17f, FontWeight.Bold, Theme.text)) }
                CopyButton("Copiar código", code, sensitive = true)
                Body("Guarde o número do pedido e o seu PIN: com eles você recupera a conta em outro celular. O número também aparece no comprovante do seu Pix.", Theme.secondary, 13.5f)
                PrismButton("Continuar") { UpgradeModel.finishPaid() }
            }
            "error", "denied" -> {
                Body("Seu código vitalício:")
                CodeDisplay(code)
                ErrorText(UpgradeModel.paidError)
                if (phase == "error") PrismButton("Tentar de novo") { UpgradeModel.activatePaid() }
                else GlassButton("Fechar") { UpgradeModel.finishPaid() }
            }
            else -> { Busy(); Body("Liberando seu acesso vitalício…") }
        }
    }
}

/** Confete leve: partículas caem e somem em ~3 s. */
@Composable
private fun Confetti() {
    var started by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { started = true }
    val p by animateFloatAsState(if (started) 1f else 0f, tween(3200, easing = LinearEasing), label = "confetti")
    val colors = Theme.prismColors + Theme.mint
    Canvas(Modifier.fillMaxWidth().height(0.dp)) {
        val rnd = java.util.Random(7)
        for (i in 0 until 34) {
            val x = rnd.nextFloat() * size.width
            val speed = 0.7f + rnd.nextFloat() * 0.8f
            val y = -20f + (p * speed) * 560.dp.toPx() * 0.6f
            val a = (1f - p).coerceIn(0f, 1f)
            drawRect(colors[i % colors.size].copy(alpha = a), Offset(x + sin(p * 6f + i) * 14f, y), Size(6.dp.toPx(), 9.dp.toPx()))
        }
    }
}

// ============================================================ PIN de recuperação

@Composable
fun PinScreen() {
    val mode = UpgradeModel.pinMode ?: return
    val mandatory = mode == "create"
    var step by remember { mutableStateOf(0) }
    var first by remember { mutableStateOf("") }
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun advance() {
        if (busy) return
        if (!isValidPin(pin)) { error = "O PIN tem 6 números."; return }
        if (step == 0) { first = pin; pin = ""; step = 1; error = null; return }
        if (pin != first) { error = "Os PINs não são iguais. Tente de novo."; pin = ""; first = ""; step = 0; return }
        busy = true; error = null
        scope.launch {
            if (UpgradeModel.debugFake) { delay(500); done = true; busy = false; return@launch }
            when (val r = Purchase.service.setPin(pin)) {
                is PurchaseResult.Ok -> done = true
                is PurchaseResult.Err -> error = r.message
            }
            busy = false
        }
    }
    GlassOverlay(onDismiss = if (mandatory) null else ({ UpgradeModel.pinMode = null })) {
        if (!mandatory) CloseRow { UpgradeModel.pinMode = null }
        HeaderIcon("lock.fill")
        if (done) {
            Title("PIN criado ✨")
            Body("Guarde seu PIN em um lugar seguro. Você vai usar o código vitalício + PIN se perder o aparelho.")
            PrismButton("Pronto") { UpgradeModel.pinMode = null }
        } else {
            Title(if (mode == "change") "Trocar PIN" else "Crie seu PIN de recuperação")
            Body(if (step == 0) "6 números. Com ele você traz sua conta vitalícia para outro celular se perder este." else "Digite o PIN de novo para confirmar.")
            CodeBoxes(pin, 6, { pin = it; error = null }, hidden = true, numeric = true, autoFocus = true, onDone = { advance() })
            ErrorText(error)
            if (busy) Busy() else PrismButton(if (step == 0) "Continuar" else "Salvar PIN") { advance() }
        }
    }
}

// ============================================================ Transferência (aparelho antigo)

@Composable
fun TransferDialog() {
    val close = { UpgradeModel.showTransfer = false }
    var code by remember { mutableStateOf<String?>(null) }
    var expires by remember { mutableLongStateOf(0L) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var generation by remember { mutableStateOf(0) }
    LaunchedEffect(generation) {
        loading = true; error = null; code = null
        if (UpgradeModel.debugFake) { delay(400); code = "K7M2P9QX"; expires = System.currentTimeMillis() + 15 * 60_000L }
        else when (val r = Purchase.service.transferCode()) {
            is PurchaseResult.Ok -> { code = r.value.code; expires = r.value.expiresAt }
            is PurchaseResult.Err -> error = r.message
        }
        loading = false
    }
    LaunchedEffect(code) { while (code != null) { now = System.currentTimeMillis(); delay(1000) } }
    val left = ((expires - now) / 1000).coerceAtLeast(0)
    GlassOverlay(onDismiss = close) {
        CloseRow(close)
        HeaderIcon("arrow.left.arrow.right")
        Title("Transferir para outro aparelho")
        when {
            loading -> { Busy(); Body("Gerando seu código…") }
            code != null && left > 0 -> {
                Body("No aparelho novo, abra a Lume › Já sou vitalício › Tenho um código de transferência e digite:")
                Box(Modifier.fillMaxWidth().glass(RoundedCornerShape(20.dp)).padding(vertical = 18.dp), contentAlignment = Alignment.Center) {
                    Text(code!!.chunked(4).joinToString("  "), style = Theme.rounded(34f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
                }
                Text("Vale por %d:%02d · uso único".format(left / 60, left % 60), style = Theme.font(14f, FontWeight.SemiBold, Theme.secondary))
                CopyButton("Copiar", code!!, prism = true, sensitive = true)
                Body("Ao usar o código, este aparelho deixa de ter o vitalício.", Theme.tertiary, 12.5f)
            }
            code != null -> { Body("O código expirou."); PrismButton("Gerar novo código") { generation++ } }
            else -> { ErrorText(error); GlassButton("Tentar de novo", "arrow.clockwise") { generation++ } }
        }
    }
}

// ============================================================ Já sou vitalício (aparelho novo)

@Composable
fun RecoverSheet() {
    val close = { UpgradeModel.showRecover = false }
    var mode by remember { mutableStateOf(0) }
    var tcode by remember { mutableStateOf("") }
    var code by remember { mutableStateOf(Access.service.lifetimeCode() ?: "") }
    var pin by remember { mutableStateOf("") }
    var orderText by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf<com.adriano.lumemusic.access.AccessInfo?>(null) }
    val scope = rememberCoroutineScope()

    fun submit() {
        if (busy) return
        busy = true; error = null
        scope.launch {
            val r = when (mode) {
                0 -> Access.service.transferWithCode(tcode)
                1 -> Access.service.transferWithPin(code, pin)
                else -> Access.service.transferWithOrder(orderText, pin)
            }
            when (r) {
                is ActivateResult.Success -> success = r.info
                is ActivateResult.Failure -> error = r.message
            }
            busy = false
        }
    }
    GlassOverlay(onDismiss = close) {
        CloseRow(close)
        val info = success
        if (info != null) {
            HeaderIcon("checkmark.seal.fill")
            Text(info.successMessage(), style = Theme.font(22f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
            Body("Sua conta Lume Vitalício está neste aparelho.")
            PrismButton("Continuar") { close() }
        } else {
            HeaderIcon("key.fill")
            Title("Já sou vitalício")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((i, label) in listOf("Código de transferência", "Código + PIN", "Esqueci meu código").withIndex()) {
                    val active = mode == i
                    val shape = RoundedCornerShape(50)
                    Box(
                        Modifier.weight(1f).heightIn(min = 52.dp).pressable(0.96f) { mode = i; error = null }
                            .then(if (active) Modifier.clip(shape).background(Theme.prismDiagonal) else Modifier.glass(shape)),
                        contentAlignment = Alignment.Center,
                    ) { Text(label, style = Theme.font(12f, FontWeight.SemiBold, if (active) Theme.onPrism else Theme.text), maxLines = 2, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 6.dp)) }
                }
            }
            if (mode == 0) {
                Body("No aparelho antigo: Ajustes › Seu acesso › Transferir para outro aparelho. Digite o código de 8 caracteres que aparecer.", Theme.secondary, 14f)
                CodeBoxes(tcode, 8, { tcode = it; error = null }, autoFocus = true, onDone = { submit() })
            } else if (mode == 2) {
                Body("Perdeu o código? Digite o número do pedido (aparece no comprovante do Pix) e o PIN de recuperação.", Theme.secondary, 14f)
                Text("Número do pedido", style = Theme.font(12.5f, FontWeight.SemiBold, Theme.secondary))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("LM-", style = Theme.rounded(24f, FontWeight.Bold, Theme.text))
                    Box(Modifier.weight(1f)) { CodeBoxes(orderText, 6, { orderText = it; error = null }, autoFocus = true, stripPrefix = "LM") }
                }
                Text("PIN de recuperação", style = Theme.font(12.5f, FontWeight.SemiBold, Theme.secondary))
                CodeBoxes(pin, 6, { pin = it; error = null }, hidden = true, numeric = true, onDone = { submit() })
                Body("Isso desconecta a Lume do outro aparelho.", Theme.tertiary, 12.5f)
            } else {
                Body("Perdeu o aparelho antigo? Digite seu código vitalício e o PIN de recuperação.", Theme.secondary, 14f)
                Text("Código vitalício", style = Theme.font(12.5f, FontWeight.SemiBold, Theme.secondary))
                CodeBoxes(code, 6, { code = it; error = null }, autoFocus = code.isEmpty())
                Text("PIN de recuperação", style = Theme.font(12.5f, FontWeight.SemiBold, Theme.secondary))
                CodeBoxes(pin, 6, { pin = it; error = null }, hidden = true, numeric = true, onDone = { submit() })
            }
            ErrorText(error)
            if (busy) Busy() else PrismButton("Trazer minha conta") { submit() }
        }
    }
}

// ============================================================ Ver meu código (PIN)

@Composable
fun RevealCodeDialog() {
    val close = { UpgradeModel.showReveal = false }
    var pin by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    fun submit() {
        if (busy) return
        if (!isValidPin(pin)) { error = "O PIN tem 6 números."; return }
        busy = true; error = null
        scope.launch {
            if (UpgradeModel.debugFake) { delay(400); UpgradeModel.revealed = "AB12CD" to "LM-7K3Q9X"; close(); return@launch }
            when (val r = Purchase.service.revealCode(pin)) {
                is PurchaseResult.Ok -> { UpgradeModel.revealed = r.value; close() }
                is PurchaseResult.Err -> { error = r.message; pin = "" }
            }
            busy = false
        }
    }
    GlassOverlay(onDismiss = close) {
        CloseRow(close)
        HeaderIcon("lock.fill")
        Title("Ver meu código")
        Body("Digite seu PIN de recuperação para mostrar o código vitalício e o número do pedido.")
        CodeBoxes(pin, 6, { pin = it; error = null }, hidden = true, numeric = true, autoFocus = true, onDone = { submit() })
        ErrorText(error)
        if (busy) Busy() else PrismButton("Mostrar") { submit() }
    }
}

// ============================================================ Tenho um código / Restaurar compra

@Composable
fun CodeEntryDialog() {
    val close = { UpgradeModel.showCodeEntry = false }
    var info by remember { mutableStateOf<com.adriano.lumemusic.access.AccessInfo?>(null) }
    GlassOverlay(onDismiss = close) {
        CloseRow(close)
        val i = info
        if (i != null) {
            AccessSuccessView(i, "Continuar") { close(); UpgradeModel.onActivated(i) }
        } else {
            AccessCodeEntry("Tenho um código", "Digite o código que você recebeu.", "Ativar") { info = it }
        }
    }
}

@Composable
fun RestoreDialog() {
    val close = { UpgradeModel.showRestore = false }
    var text by remember { mutableStateOf(Access.service.lifetimeCode() ?: Access.service.lifetimeOrder() ?: "") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var ok by remember { mutableStateOf<com.adriano.lumemusic.access.AccessInfo?>(null) }
    val scope = rememberCoroutineScope()
    val closeKeyboard = rememberKeyboardCloser()
    fun submit() {
        if (busy) return
        busy = true; error = null
        scope.launch {
            when (val r = Purchase.service.restore(text)) {
                is ActivateResult.Success -> ok = r.info
                is ActivateResult.Failure -> error = r.message
            }
            busy = false
        }
    }
    GlassOverlay(onDismiss = close) {
        CloseRow(close)
        val info = ok
        if (info != null) {
            HeaderIcon("checkmark.seal.fill")
            Text(info.successMessage(), style = Theme.font(22f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
            PrismButton("Continuar") { close() }
        } else {
            HeaderIcon("arrow.counterclockwise")
            Title("Restaurar compra")
            Body("Digite o código vitalício ou o número do pedido (LM-XXXXXX). Funciona neste aparelho; para trazer a conta de outro, use Já sou vitalício.", Theme.secondary, 14f)
            BasicTextField(
                text, { text = it.uppercase().take(12); error = null }, singleLine = true,
                textStyle = Theme.rounded(20f, FontWeight.Bold, Theme.text), cursorBrush = SolidColor(Theme.rose),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { closeKeyboard(); submit() }),
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).glass(RoundedCornerShape(16.dp)).padding(horizontal = 16.dp, vertical = 14.dp),
            )
            ErrorText(error)
            KeyboardOkButton { if (text.isNotBlank()) submit() }
            if (busy) Busy() else PrismButton("Restaurar") { submit() }
            GlassButton("Já sou vitalício em outro aparelho") { close(); UpgradeModel.showRecover = true }
        }
    }
}

// ============================================================ Atualização

@Composable
fun UpdateDialog() {
    val info = UpdateController.available ?: return
    val ctx = LocalContext.current
    val phase = UpdateController.phase
    GlassOverlay(onDismiss = if (info.mandatory || phase == UpdatePhase.Downloading) null else ({ UpdateController.later() })) {
        HeaderIcon("system.update")
        Title("Nova versão ${info.versionName} disponível")
        if (info.notes.isNotBlank()) {
            Column(Modifier.fillMaxWidth().heightIn(max = 180.dp).glass(RoundedCornerShape(18.dp)).verticalScroll(rememberScrollState()).padding(14.dp)) {
                Text(info.notes.trim(), style = Theme.font(14f, color = Theme.text))
            }
        }
        when (phase) {
            UpdatePhase.Downloading -> {
                val p = UpdateController.progress
                val got = UpdateController.downloadedBytes
                val total = UpdateController.totalBytes
                fun fmtMb(bytes: Long) = String.format(java.util.Locale.forLanguageTag("pt-BR"), "%.1f MB", bytes / 1_048_576.0)
                Box(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(Theme.fillStrong)) {
                    Box(Modifier.fillMaxWidth(if (total > 0) p.coerceIn(0.03f, 1f) else 0.35f).fillMaxSize().background(Theme.prismHorizontal))
                }
                val label = if (total > 0) "Baixando… ${(p * 100).toInt()}% · ${fmtMb(got)} / ${fmtMb(total)}" else "Baixando… ${fmtMb(got)}"
                Body(label, Theme.secondary, 14f)
            }
            UpdatePhase.NeedPermission -> {
                Body("Libere \"Instalar apps desconhecidos\" para a Lume nas configurações que abriram. Ao voltar, a atualização continua sozinha.", Theme.secondary, 14f)
                PrismButton("Abrir configurações") { UpdateController.start(ctx) }
            }
            else -> {
                ErrorText(UpdateController.error)
                if (phase != UpdatePhase.Error) {
                    Body("O download e a instalação acontecem direto por aqui, sem perder suas playlists.", Theme.tertiary, 12.5f)
                }
                PrismButton(if (phase == UpdatePhase.Error) "Tentar de novo" else "Atualizar agora") { UpdateController.start(ctx) }
                if (phase == UpdatePhase.Error) {
                    GlassButton("Baixar pelo navegador") { UpdateController.openInBrowser(ctx) }
                }
            }
        }
        if (!info.mandatory && phase != UpdatePhase.Downloading) GlassButton("Depois") { UpdateController.later() }
    }
}

// ============================================================ Host global

/** Fica sobre tudo no RootScreen: polling do pedido, lembretes de prazo e todos os pop-ups. */
@Composable
fun UpgradeHost(onboarding: Boolean) {
    val ctx = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by Access.service.state.collectAsState()
    val blocked = onboarding || state is AccessState.Locked

    LaunchedEffect(Unit) { UpgradeModel.init() }

    // Polling do pedido pendente: só em primeiro plano (pausa em segundo plano e retoma ao voltar).
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            UpdateController.resume(ctx)
            var waited = 0L
            while (true) {
                delay(1000); waited += 1000
                if (waited >= UpgradeModel.pollDelayMs()) { waited = 0; if (UpgradeModel.hasPending()) UpgradeModel.pollOnce() }
            }
        }
    }
    // Lembretes de 3 e 1 dia.
    LaunchedEffect(state, blocked) {
        if (blocked) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { (state as? AccessState.Active)?.info?.let { UpgradeModel.checkMilestones(it) } }
    }

    val anyOther = UpgradeModel.welcomeDays != null || UpgradeModel.showUpgrade || UpgradeModel.paidCode != null || UpgradeModel.pinMode != null ||
        UpgradeModel.showReveal || UpgradeModel.showTransfer || UpgradeModel.showRecover || UpgradeModel.showRestore || UpgradeModel.showCodeEntry
    if (!blocked && !anyOther && UpdateController.available != null) UpdateDialog()
    UpgradeModel.welcomeDays?.let { if (!blocked) WelcomeDialog(it, UpgradeModel.welcomeReminder) }
    if (UpgradeModel.showUpgrade) UpgradeSheet()
    if (UpgradeModel.showCodeEntry) CodeEntryDialog()
    if (UpgradeModel.showRestore) RestoreDialog()
    if (UpgradeModel.showReveal) RevealCodeDialog()
    if (UpgradeModel.showRecover) RecoverSheet()
    if (UpgradeModel.showTransfer) TransferDialog()
    if (UpgradeModel.paidCode != null) PaidDialog()
    if (UpgradeModel.pinMode != null) PinScreen()
}
