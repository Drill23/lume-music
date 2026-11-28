package com.adriano.lumemusic.engine

import java.text.Normalizer

/** Utilidades de texto do motor de descoberta (App/ArtworkResolver.swift → DiscText). */
object DiscText {
    private val reBrackets = Regex("""\([^)]*\)|\[[^\]]*\]""")
    private val reSuffixVersion = Regex(
        """\s[-–—]\s*(ao vivo|live|remaster(ed)?|acoustic|ac[uú]stico|versão|version|radio edit|single version|topic).*$""",
        RegexOption.IGNORE_CASE,
    )
    private val reFeat = Regex("""\s(feat\.?|ft\.?|featuring|part\.?|com)\s.*$""", RegexOption.IGNORE_CASE)
    private val reNonAlnum = Regex("""[^a-z0-9]+""")
    private val reSplitFeat = Regex("""\s(feat\.?|ft\.?|x|e|and|com|part\.?)\s""", RegexOption.IGNORE_CASE)

    private val reMarks = Regex("""\p{M}+""")

    fun fold(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(reMarks, "")

    /** minúsculas, sem acentos, sem (feat ...), "- Ao Vivo", parênteses/colchetes e pontuação. */
    fun normalize(s: String): String {
        var out = s
        out = out.replace(reBrackets, " ")
        out = out.replace(reSuffixVersion, "")
        out = out.replace(reFeat, "")
        out = fold(out).lowercase()
        out = out.replace("&", " e ")
        out = out.replace(reNonAlnum, " ")
        return out.trim()
    }

    fun artistMatches(a: String, b: String): Boolean {
        if (a.equals(b, ignoreCase = true)) return a.isNotEmpty()
        val na = normalize(a)
        val nb = normalize(b)
        if (na.isEmpty() || nb.isEmpty()) return false
        if (na == nb || na.contains(nb) || nb.contains(na)) return true
        val partsA = splitArtists(a)
        val partsB = splitArtists(b)
        for (x in partsA) for (y in partsB) if (x == y) return true
        return false
    }

    fun splitArtists(s: String): List<String> =
        s.replace(reSplitFeat, ",")
            .split(',', '&', ';', '/')
            .map { normalize(it) }
            .filter { it.isNotEmpty() }

    fun titleMatches(a: String, b: String): Boolean {
        val na = normalize(a)
        val nb = normalize(b)
        if (na.isEmpty() || nb.isEmpty()) return false
        return na == nb
    }

    fun titleLooselyMatches(a: String, b: String): Boolean {
        val na = normalize(a)
        val nb = normalize(b)
        if (na.isEmpty() || nb.isEmpty()) return false
        if (na == nb) return true
        val short = if (na.length <= nb.length) na else nb
        val long = if (na.length <= nb.length) nb else na
        return short.length >= 5 && long.startsWith("$short ")
    }

    /** "Artista - Topic" → "Artista"; mantém colaborações (para busca). */
    fun searchArtist(s: String): String =
        s.replace(" - Topic", "", ignoreCase = true).replace("VEVO", "", ignoreCase = true).trim()

    private val reTitleParens = Regex("""\s*[\(\[][^\)\]]*[\)\]]""")
    private val reTitleDash = Regex("""\s[-–—|]\s.*$""")

    fun searchTitle(s: String): String {
        var out = s.replace(reTitleParens, "")
        out = out.replace(reTitleDash, "")
        out = out.trim()
        return out.ifEmpty { s }
    }

    fun year(date: String?): String = if (date != null && date.length >= 4) date.take(4) else ""

    private val reApple = Regex("""\d{2,4}x\d{2,4}(bb|cc)""")

    fun upscaleApple(url: String): String = url.replace(reApple, "1200x1200bb")
}
