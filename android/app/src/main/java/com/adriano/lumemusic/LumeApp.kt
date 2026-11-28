package com.adriano.lumemusic

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.engine.DiscNet
import com.adriano.lumemusic.platform.Haptics
import okio.Path.Companion.toOkioPath

class LumeApp : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        DiscNet.cacheDir = cacheDir
        Haptics.init(this)
        com.adriano.lumemusic.ui.AppModel.loadPrefs(this)
        LibraryStore.init(this)
        DownloadManager.init(this)
        com.adriano.lumemusic.ui.HomeStore.init(this)
        Access.init(this)
        AudioPlayer.init(this)
        com.adriano.lumemusic.data.LibraryBackup.init(this)
        com.adriano.lumemusic.data.ListenBrainz.init(this)
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { DiscNet.client })) }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.22).build() }
            .diskCache { DiskCache.Builder().directory(cacheDir.resolve("img").toOkioPath()).maxSizeBytes(400L * 1024 * 1024).build() }
            .crossfade(220)
            .build()
}
