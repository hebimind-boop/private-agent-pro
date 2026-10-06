package com.orailnoor.privateagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache

class BackgroundEngineReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        val appContext = context.applicationContext ?: context
        try {
            val engine = FlutterEngineCache
                .getInstance()
                .get("myCachedEngine")
            if (engine == null) {
                Log.w("PrivateAgent", "Background engine myCachedEngine was not found in cache yet")
                return
            }

            Log.d(
                "PrivateAgent",
                "Registering accessibility channel on myCachedEngine " +
                    "(engine=${System.identityHashCode(engine)}, " +
                    "dartExecuting=${engine.dartExecutor?.isExecutingDart})"
            )
            MainActivity.registerAccessibilityChannel(engine, appContext)
        } catch (e: Exception) {
            Log.e("PrivateAgent", "Error in BackgroundEngineReceiver: ${e.message}", e)
        }
    }
}
