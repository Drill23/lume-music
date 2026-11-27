package com.adriano.lumemusic.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.data.DiscoverFeed
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.engine.ChartList
import com.adriano.lumemusic.engine.ChartPlace
import com.adriano.lumemusic.engine.ChartsService
import com.adriano.lumemusic.engine.DiscText
import com.adriano.lumemusic.engine.DiscoveryService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// ---------------- Gêneros do onboarding ----------------

object OnboardingGenres {
    const val KEY = "lume.onboarding.genres"

    private val aliases = mapOf(
        "funk" to "funk_br", "trap" to "funk_br", "baile funk" to "funk_br", "funk carioca" to "funk_br",
        "pagode" to "pagode", "samba" to "pagode", "mpb" to "mpb", "bossa" to "mpb", "bossa nova" to "mpb",
        "forro" to "forro", "piseiro" to "forro", "arrocha" to "forro",
        "gospel" to "gospel", "louvor" to "gospel", "religioso" to "gospel", "crista" to "gospel",
        "rap" to "hiphop", "hip hop" to "hiphop", "hiphop" to "hiphop",
        "eletronica" to "eletronica", "dance" to "eletronica", "edm" to "eletronica", "house" to "eletronica",
        "r e b" to "rnb", "rnb" to "rnb", "soul" to "rnb",
        "latina" to "latina", "latino" to "latina", "reggaeton" to "latina", "musica latina" to "latina",
        "k pop" to "kpop", "kpop" to "kpop", "classica" to "classica", "erudita" to "classica",
        "trilhas" to "soundtrack", "trilha sonora" to "soundtrack", "games" to "soundtrack",
        "alternativo" to "indie", "indie" to "indie", "pop" to "pop", "rock" to "rock", "metal" to "metal",
        "jazz" to "jazz", "reggae" to "reggae", "country" to "country", "sertanejo" to "sertanejo", "sertaneja" to "sertanejo",
    )

    /**
     * Gêneros escolhidos no onboarding. Leitura tolerante: a chave `lume.onboarding.genres` (ou "genres", gravada pelo
     * onboarding atual) pode vir como conjunto de strings, texto separado por vírgula/;/| ou nomes soltos, em qualquer
     * um dos arquivos de preferências do app.
     */
    fun selected(ctx: Context?): List<MusicGenre> {
        if (ctx == null) return emptyList()
        val names = LinkedHashSet<String>()
        for (file in listOf("lume_prefs", "lume.onboarding", "lume_onboarding", ctx.packageName + "_preferences")) {
            val prefs = try { ctx.getSharedPreferences(file, Context.MODE_PRIVATE) } catch (_: Exception) { continue }
            for (key in listOf(KEY, "genres")) {
                val v = try { prefs.all[key] } catch (_: Exception) { null } ?: continue
                when (v) {
                    is Set<*> -> v.forEach { names.add(it.toString()) }
                    is String -> v.split(',', ';', '|').forEach { names.add(it) }
                    is Collection<*> -> v.forEach { names.add(it.toString()) }
                }
            }
            if (names.isNotEmpty()) break
        }
        val out = mutableListOf<MusicGenre>()
        for (n in names) {
            val g = match(n)
            if (g != null && out.none { it.id == g.id }) out.add(g)
        }
        return out
    }

    fun match(name: String): MusicGenre? {
        val key = DiscText.normalize(name)
        if (key.isEmpty()) return null
        aliases[key]?.let { id -> MusicGenre.all.firstOrNull { it.id == id }?.let { return it } }
        MusicGenre.all.firstOrNull { it.id == key || DiscText.normalize(it.title) == key }?.let { return it }
        return MusicGenre.all.firstOrNull { g ->
            val t = DiscText.normalize(g.title)
            t.contains(key) || (key.length > 3 && key.contains(t))
        }
    }
}

// ---------------- Estado da Home ----------------

/**
 * Dono dos dados da Home. Mostra o cache em disco NA HORA e atualiza em segundo plano (stale-while-revalidate);
 * tudo em paralelo, sem bloquear a thread principal (as leituras de disco/rede acontecem em Dispatchers.IO).
 */
object HomeStore {
    private const val PLACE_KEY = "lume.home.chartPlace"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var appCtx: Context? = null
    private var started = false

    val lists = mutableStateMapOf<String, ChartList>()
    private val loading = mutableStateMapOf<String, Boolean>()
    var genreMixes by mutableStateOf<List<PersonalizedMix>>(emptyList()); private set
    /** Primeira rodada de carga terminou (com ou sem dados). */
    var settled by mutableStateOf(false); private set

    /** País do usuário (Locale) — usado na vitrine e como padrão do Top 10. */
    val homePlace: ChartPlace = ChartPlace.userPlace
    var place by mutableStateOf(homePlace); private set

    val feed: DiscoverFeed? get() = AppModel.feed
    val current: ChartList? get() = lists[place.id]
    val homeList: ChartList? get() = lists[homePlace.id]
    val isLoadingCurrent: Boolean get() = loading[place.id] == true

    fun init(ctx: Context) {
        appCtx = ctx.applicationContext
        val saved = ctx.getSharedPreferences("lume_prefs", Context.MODE_PRIVATE).getString(PLACE_KEY, null)
        ChartPlace.place(saved)?.let { place = it }
    }

    // ---- Início ----

    fun start() {
        if (started) return
        started = true
        scope.launch { bootstrap() }
    }

    private suspend fun bootstrap() {
        // 1) Cache instantâneo (disco → memória), tudo em paralelo.
        coroutineScope {
            val a = async(Dispatchers.IO) { ChartsService.cached(place) }
            val b = async(Dispatchers.IO) { ChartsService.cached(homePlace) }
            val c = async(Dispatchers.IO) { DiscoveryService.cachedFeed() }
            a.await()?.let { lists[place.id] = it }
            b.await()?.let { lists[homePlace.id] = it }
            c.await()?.let { AppModel.setFeedIfEmpty(it) }
        }
        reloadGenreMixesFromCache()

        // 2) Revalidação em segundo plano: paradas do país do usuário + selecionado + feed + mixes.
        coroutineScope {
            val tasks = mutableListOf(
                async { revalidate(homePlace) },
                async { refreshFeedIfNeeded() },
                async { refreshGenreMixes() },
            )
            if (place.id != homePlace.id) tasks.add(async { revalidate(place) })
            tasks.awaitAll()
        }
        settled = true

        // 3) Pré-carrega as paradas mais prováveis do seletor, sem pressa.
        val next = ChartPlace.all.filter { it.id != place.id && it.id != homePlace.id }.take(5)
        ChartsService.prefetch(next)
    }

    suspend fun refresh() {
        coroutineScope {
            val tasks = mutableListOf(
                async { revalidate(homePlace, force = true) },
                async { AppModel.loadFeed(force = true) },
                async { refreshGenreMixes(force = true) },
            )
            if (place.id != homePlace.id) tasks.add(async { revalidate(place, force = true) })
            tasks.awaitAll()
        }
    }

    // ---- Paradas ----

    fun select(p: ChartPlace) {
        if (p.id == place.id) return
        place = p
        appCtx?.getSharedPreferences("lume_prefs", Context.MODE_PRIVATE)?.edit()?.putString(PLACE_KEY, p.id)?.apply()
        scope.launch {
            if (lists[p.id] == null) ChartsService.cached(p)?.let { lists[p.id] = it }
            revalidate(p)
            // Vizinhos no seletor ficam prontos para a próxima troca.
            val i = ChartPlace.all.indexOf(p)
            if (i >= 0) {
                val near = listOf(i - 1, i + 1, i + 2).filter { it in ChartPlace.all.indices }.map { ChartPlace.all[it] }
                ChartsService.prefetch(near)
                for (n in near) if (lists[n.id] == null) ChartsService.cached(n)?.let { lists[n.id] = it }
            }
        }
    }

    suspend fun revalidate(p: ChartPlace, force: Boolean = false) {
        loading[p.id] = true
        try {
            ChartsService.load(p, force)?.let { lists[p.id] = it }
        } finally { loading.remove(p.id) }
    }

    private suspend fun refreshFeedIfNeeded() {
        val f = AppModel.feed
        if (f != null && System.currentTimeMillis() - f.updatedAt < 20 * 60_000L) return
        AppModel.loadFeed(force = true)
    }

    // ---- "Para você" por gênero ----

    fun mix(g: MusicGenre, tracks: List<com.adriano.lumemusic.data.Track>) = PersonalizedMix(
        id = "genre_${g.id}", title = g.title, subtitle = g.subtitle, tag = "PARA VOCÊ", icon = g.icon,
        hexA = g.hexA, hexB = g.hexB, tracks = tracks.take(30),
    )

    /** Gêneros do onboarding; se não houver, os estilos mais populares da região do usuário. */
    private fun preferredGenres(): List<MusicGenre> {
        val chosen = OnboardingGenres.selected(appCtx)
        if (chosen.isNotEmpty()) return chosen.take(4)
        // Sem escolha e sem histórico: sugere estilos populares da região para a Home nunca ficar vazia.
        if (LibraryStore.recentTracks.isNotEmpty()) return emptyList()
        val ids = if (homePlace.id == "br") listOf("sertanejo", "pop", "funk_br") else listOf("pop", "hiphop", "rock")
        return ids.mapNotNull { id -> MusicGenre.all.firstOrNull { it.id == id } }
    }

    private suspend fun reloadGenreMixesFromCache() {
        val genres = preferredGenres()
        if (genres.isEmpty()) return
        val out = genres.mapNotNull { g -> ChartsService.cachedGenreSongs(g)?.let { mix(g, it) } }
        if (genreMixes.isEmpty() && out.isNotEmpty()) genreMixes = out
    }

    suspend fun refreshGenreMixes(force: Boolean = false) {
        val genres = preferredGenres()
        if (genres.isEmpty()) { genreMixes = emptyList(); return }
        val mixes = coroutineScope {
            genres.map { g -> async(Dispatchers.IO) { ChartsService.genreSongs(g, force).let { if (it.isEmpty()) null else mix(g, it) } } }.awaitAll()
        }.filterNotNull()
        if (mixes.isNotEmpty()) genreMixes = mixes
    }
}
