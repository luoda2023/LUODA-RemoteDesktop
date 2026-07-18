package com.luoda.remote

import android.app.Application
import android.os.Build
import android.util.Log
import ffi.FFI
import java.io.File

class MainApplication : Application() {
    companion object {
        private const val TAG = "MainApplication"
    }

    override fun onCreate() {
        super.onCreate()
        writeStartupLog(
            "App start; sdk=${Build.VERSION.SDK_INT}; abis=${Build.SUPPORTED_ABIS.joinToString(",")}"
        )
        if (!FFI.isLoaded) {
            val error = FFI.loadError
            Log.e(TAG, "Failed to load libluoda.so", error)
            writeStartupLog("Failed to load libluoda.so: $error")
            return
        }
        try {
            FFI.onAppStart(applicationContext)
            writeStartupLog("libluoda.so loaded and onAppStart completed")
        } catch (error: Throwable) {
            Log.e(TAG, "Native onAppStart failed", error)
            writeStartupLog("Native onAppStart failed: $error")
        }
    }

    private fun writeStartupLog(message: String) {
        try {
            val logDir = File(filesDir, "logs")
            logDir.mkdirs()
            File(logDir, "android_startup.log").appendText(
                "${System.currentTimeMillis()} $message\n"
            )
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to persist startup log", error)
        }
    }
}
