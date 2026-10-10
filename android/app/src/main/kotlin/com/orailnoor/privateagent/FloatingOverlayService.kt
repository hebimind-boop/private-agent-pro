package com.orailnoor.privateagent

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat

class FloatingOverlayService : Service(), View.OnTouchListener {
    companion object {
        const val TAG = "FloatingOverlayService"
        const val CHANNEL_ID = "floating_bubble_service"
        const val NOTIFICATION_ID = 8842
        var isRunning = false

        fun start(context: Context) {
            val intent = Intent(context, FloatingOverlayService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start FloatingOverlayService: ${e.message}", e)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, FloatingOverlayService::class.java)
            try {
                context.stopService(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop FloatingOverlayService: ${e.message}", e)
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var params: WindowManager.LayoutParams? = null

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false
    private var lastUpdateTime = 0L
    private var snapAnimator: ValueAnimator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        // 1. Start foreground notification immediately BEFORE touching WindowManager
        startForegroundNotification()
        // 2. Safely create floating view only if overlay permissions are valid
        createFloatingView()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Ensure foreground notification remains valid
        startForegroundNotification()
        // Return START_NOT_STICKY to avoid infinite crash loops if the system kills the service
        return START_NOT_STICKY
    }

    private fun startForegroundNotification() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Floating Assistant Bubble",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps BoopAgent floating assistant active"
                    setShowBadge(false)
                }
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                manager?.createNotificationChannel(channel)
            }

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = if (launchIntent != null) {
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                PendingIntent.getActivity(this, 0, launchIntent, flags)
            } else null

            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("BoopAgent Active")
                .setContentText("Floating Assistant Bubble is running")
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            startForeground(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground notification: ${e.message}", e)
        }
    }

    private fun createFloatingView() {
        try {
            // Verify overlay permission before adding view to prevent WindowManager.BadTokenException
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                Log.w(TAG, "Overlay permission not granted; skipping view creation")
                return
            }

            if (overlayView != null) {
                return
            }

            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val density = resources.displayMetrics.density
            val bubbleSize = (56 * density).toInt()

            params = WindowManager.LayoutParams(
                bubbleSize,
                bubbleSize,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = (resources.displayMetrics.widthPixels - bubbleSize - (16 * density).toInt())
                y = (resources.displayMetrics.heightPixels * 0.35).toInt()
            }

            // Create OLED minimalist circle view
            val container = FrameLayout(this).apply {
                layoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#0A0A0A"))
                    setStroke((1.5 * density).toInt(), Color.parseColor("#FFFFFF"))
                }
            }

            val icon = ImageView(this).apply {
                val iconPadding = (14 * density).toInt()
                setPadding(iconPadding, iconPadding, iconPadding, iconPadding)
                setImageResource(android.R.drawable.ic_menu_send)
                setColorFilter(Color.WHITE)
            }
            container.addView(icon)

            container.setOnTouchListener(this)
            overlayView = container

            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create floating view: ${e.message}", e)
        }
    }

    override fun onTouch(v: View?, event: MotionEvent?): Boolean {
        if (event == null || params == null || windowManager == null || overlayView == null) return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                snapAnimator?.cancel()
                initialX = params!!.x
                initialY = params!!.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                lastUpdateTime = SystemClock.uptimeMillis()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY
                if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                    isDragging = true
                }
                if (isDragging) {
                    val now = SystemClock.uptimeMillis()
                    // Throttle updates to ~16ms (approx 60fps) to prevent binder IPC saturation
                    if (now - lastUpdateTime >= 16L) {
                        lastUpdateTime = now
                        val density = resources.displayMetrics.density
                        val bubbleHeight = overlayView?.height ?: (56 * density).toInt()
                        val minY = (16 * density).toInt()
                        val maxY = resources.displayMetrics.heightPixels - bubbleHeight - (32 * density).toInt()
                        params!!.x = initialX + dx.toInt()
                        params!!.y = (initialY + dy.toInt()).coerceIn(minY, maxY)
                        try {
                            windowManager?.updateViewLayout(overlayView, params)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating layout on drag: ${e.message}")
                        }
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!isDragging) {
                    // Tap detected! Bring PrivateAgent app to foreground
                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }
                    if (launchIntent != null) {
                        try {
                            startActivity(launchIntent)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to launch main activity: ${e.message}")
                        }
                    }
                } else {
                    // Drag ended: smoothly snap bubble to nearest screen edge (left or right)
                    snapToNearestEdge()
                }
                return true
            }
        }
        return false
    }

    private fun snapToNearestEdge() {
        val currentParams = params ?: return
        val currentView = overlayView ?: return
        val wm = windowManager ?: return

        try {
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val density = displayMetrics.density
            val bubbleWidth = currentView.width.takeIf { it > 0 } ?: (56 * density).toInt()
            val margin = (16 * density).toInt()

            val bubbleCenterX = currentParams.x + (bubbleWidth / 2)
            val targetX = if (bubbleCenterX < screenWidth / 2) {
                margin
            } else {
                screenWidth - bubbleWidth - margin
            }

            snapAnimator?.cancel()
            snapAnimator = ValueAnimator.ofInt(currentParams.x, targetX).apply {
                duration = 250L
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    if (overlayView != null && overlayView?.isAttachedToWindow == true) {
                        currentParams.x = animator.animatedValue as Int
                        try {
                            wm.updateViewLayout(overlayView, currentParams)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating layout on snap: ${e.message}")
                        }
                    }
                }
                start()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to snap to edge: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        snapAnimator?.cancel()
        snapAnimator = null
        if (overlayView != null && windowManager != null) {
            try {
                windowManager?.removeView(overlayView)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlayView: ${e.message}")
            }
            overlayView = null
        }
        try {
            stopForeground(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping foreground: ${e.message}")
        }
    }
}
