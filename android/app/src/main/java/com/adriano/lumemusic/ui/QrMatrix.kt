package com.adriano.lumemusic.ui

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/** Matriz do QR Code (sem margem) gerada no aparelho com zxing; o desenho em módulos inteiros fica nítido. */
object QrMatrix {
    fun build(text: String): Array<BooleanArray>? = try {
        val m = QRCodeWriter().encode(
            text, BarcodeFormat.QR_CODE, 0, 0,
            mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0, EncodeHintType.CHARACTER_SET to "UTF-8"),
        )
        Array(m.height) { y -> BooleanArray(m.width) { x -> m.get(x, y) } }
    } catch (_: Exception) { null }
}
