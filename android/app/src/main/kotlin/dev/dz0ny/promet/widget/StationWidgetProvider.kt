package dev.dz0ny.promet.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import dev.dz0ny.promet.MainActivity
import dev.dz0ny.promet.R
import java.util.concurrent.Executors

/** Per-widget settings: the station and which readings to show. */
data class WidgetConfig(
    val stationId: Int?,
    val stationName: String?,
    val camera: Boolean = true,
    val wind: Boolean = true,
    val rain: Boolean = true,
    val minMax: Boolean = true,
    val humidity: Boolean = false,
    val dew: Boolean = false,
    val pressure: Boolean = false,
) {
    companion object {
        private const val PREFS = "station_widget"

        fun load(ctx: Context, widgetId: Int): WidgetConfig {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            fun b(k: String, def: Boolean) = p.getBoolean("${widgetId}_$k", def)
            val id = p.getInt("${widgetId}_station", -1)
            return WidgetConfig(
                stationId = id.takeIf { it >= 0 },
                stationName = p.getString("${widgetId}_name", null),
                camera = b("camera", true), wind = b("wind", true), rain = b("rain", true),
                minMax = b("minmax", true), humidity = b("humidity", false),
                dew = b("dew", false), pressure = b("pressure", false),
            )
        }

        fun save(ctx: Context, widgetId: Int, c: WidgetConfig) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                putInt("${widgetId}_station", c.stationId ?: -1)
                putString("${widgetId}_name", c.stationName)
                putBoolean("${widgetId}_camera", c.camera)
                putBoolean("${widgetId}_wind", c.wind)
                putBoolean("${widgetId}_rain", c.rain)
                putBoolean("${widgetId}_minmax", c.minMax)
                putBoolean("${widgetId}_humidity", c.humidity)
                putBoolean("${widgetId}_dew", c.dew)
                putBoolean("${widgetId}_pressure", c.pressure)
            }.apply()
        }

        fun delete(ctx: Context, widgetId: Int) {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            p.edit().apply { p.all.keys.filter { it.startsWith("${widgetId}_") }.forEach(::remove) }.apply()
        }
    }
}

/** One reading line: label and value. */
data class Metric(val label: String, val value: String)

/** The enabled readings in a fixed priority order (same as the iOS widget);
 *  when space runs out the later ones are dropped. */
fun metrics(r: StationReading, c: WidgetConfig, compact: Boolean): List<Metric> = buildList {
    if (c.wind && r.wind != null) add(Metric("Veter", Fmt.wind(r, withGust = !compact)))
    if (c.rain && r.rain != null) add(Metric("Padavine", "${Fmt.decimal(r.rain)} mm"))
    if (c.minMax && (r.minTemp != null || r.maxTemp != null))
        add(Metric("Min / maks", "${Fmt.degrees(r.minTemp)} / ${Fmt.degrees(r.maxTemp)}"))
    if (c.humidity && r.humidity != null) add(Metric("Vlaga", "${r.humidity} %"))
    if (c.dew && r.dew != null) add(Metric("Rosišče", Fmt.temp(r.dew)))
    if (c.pressure && r.pressure != null) add(Metric("Tlak", "${r.pressure} hPa"))
}

/** The app's temperature scale (AppTheme.temperatureColor). */
fun temperatureColor(c: Double?): Int = when {
    c == null -> 0xFF6B7B8C.toInt()
    c <= -10 -> 0xFF4A148C.toInt()
    c <= 0 -> 0xFF1E88E5.toInt()
    c <= 5 -> 0xFF26C6DA.toInt()
    c <= 12 -> 0xFF66BB6A.toInt()
    c <= 20 -> 0xFFD4E157.toInt()
    c <= 27 -> 0xFFFFB300.toInt()
    c <= 33 -> 0xFFFB8C00.toInt()
    else -> 0xFFE53935.toInt()
}

private enum class WidgetSize { SMALL, MEDIUM, LARGE }

/**
 * Home screen widget with one weather station. It fetches the ceste.si feed
 * itself (every 30 minutes, on resize and after settings change), so it
 * works without the app running; the last good reading is kept on disk.
 */
class StationWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        refresh(ctx, ids, goAsync())
    }

    override fun onAppWidgetOptionsChanged(ctx: Context, mgr: AppWidgetManager, id: Int, options: Bundle) {
        // Resized: redraw from what is on disk, no network needed.
        render(ctx, mgr, id, fetch = false)
    }

    override fun onDeleted(ctx: Context, ids: IntArray) {
        ids.forEach { WidgetConfig.delete(ctx, it) }
    }

    companion object {
        private val executor = Executors.newSingleThreadExecutor()

        /** Fetch and redraw [ids] off the main thread. */
        fun refresh(ctx: Context, ids: IntArray, pending: android.content.BroadcastReceiver.PendingResult? = null) {
            val app = ctx.applicationContext
            executor.execute {
                try {
                    val mgr = AppWidgetManager.getInstance(app)
                    ids.forEach { render(app, mgr, it, fetch = true) }
                } finally {
                    pending?.finish()
                }
            }
        }

        fun refreshAll(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            refresh(ctx, mgr.getAppWidgetIds(ComponentName(ctx, StationWidgetProvider::class.java)))
        }

        private fun sizeOf(mgr: AppWidgetManager, id: Int): WidgetSize {
            val o = mgr.getAppWidgetOptions(id)
            // Portrait: the narrow width and the tall height.
            val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            return when {
                w in 1 until 200 -> WidgetSize.SMALL
                h >= 260 -> WidgetSize.LARGE
                w == 0 -> WidgetSize.SMALL
                else -> WidgetSize.MEDIUM
            }
        }

        fun render(ctx: Context, mgr: AppWidgetManager, id: Int, fetch: Boolean) {
            val cfg = WidgetConfig.load(ctx, id)
            val size = sizeOf(mgr, id)
            val stationId = cfg.stationId
            val views = if (stationId == null) {
                unconfigured(ctx, size)
            } else {
                var reading: StationReading? = null
                var image: Bitmap? = null
                if (fetch) {
                    reading = runCatching { StationFeed.stations().firstOrNull { it.id == stationId } }.getOrNull()
                    if (reading != null && cfg.camera) image = StationFeed.cameraBitmap(reading.cameraLink)
                    if (reading != null) StationFeed.save(ctx, reading, image)
                }
                reading = reading ?: StationFeed.loadReading(ctx, stationId)
                if (cfg.camera && image == null) image = StationFeed.loadImage(ctx, stationId)
                if (reading == null) unavailable(ctx, size, cfg.stationName)
                else build(ctx, size, reading, cfg, if (cfg.camera) image else null)
            }
            views.setOnClickPendingIntent(android.R.id.background, openApp(ctx))
            mgr.updateAppWidget(id, views)
        }

        private fun layoutFor(size: WidgetSize) = when (size) {
            WidgetSize.SMALL -> R.layout.widget_station_small
            WidgetSize.MEDIUM -> R.layout.widget_station_medium
            WidgetSize.LARGE -> R.layout.widget_station_large
        }

        private fun build(ctx: Context, size: WidgetSize, r: StationReading, cfg: WidgetConfig, image: Bitmap?): RemoteViews {
            val v = RemoteViews(ctx.packageName, layoutFor(size))
            v.setTextViewText(R.id.name, r.name)
            v.setTextViewText(R.id.temp, Fmt.degrees(r.temp))
            v.setTextViewText(R.id.updated, "ob ${Fmt.time(r.timestamp)}")
            v.setTextColor(R.id.dot, temperatureColor(r.temp))
            if (image != null) {
                v.setImageViewBitmap(R.id.bg_image, image)
                v.setViewVisibility(R.id.scrim, View.VISIBLE)
            } else {
                v.setImageViewBitmap(R.id.bg_image, gradient(r.temp))
                v.setViewVisibility(R.id.scrim, View.GONE)
            }
            v.setContentDescription(android.R.id.background, "${r.name}, ${Fmt.temp(r.temp)}")
            when (size) {
                WidgetSize.SMALL -> fillLines(v, metrics(r, cfg, compact = true), listOf(R.id.m1, R.id.m2))
                WidgetSize.MEDIUM -> {
                    val list = metrics(r, cfg, compact = true)
                    fillLines(v, list, listOf(R.id.m1, R.id.m2, R.id.m3, R.id.m4))
                    v.setViewVisibility(R.id.metrics, if (list.isEmpty()) View.GONE else View.VISIBLE)
                }
                WidgetSize.LARGE -> fillGrid(v, metrics(r, cfg, compact = false))
            }
            return v
        }

        private fun fillLines(v: RemoteViews, list: List<Metric>, ids: List<Int>) {
            ids.forEachIndexed { i, id ->
                val m = list.getOrNull(i)
                if (m == null) v.setViewVisibility(id, View.GONE)
                else {
                    v.setViewVisibility(id, View.VISIBLE)
                    v.setTextViewText(id, "${m.label}  ${m.value}")
                }
            }
        }

        private val cells = listOf(
            Triple(R.id.c1, R.id.c1_label, R.id.c1_value), Triple(R.id.c2, R.id.c2_label, R.id.c2_value),
            Triple(R.id.c3, R.id.c3_label, R.id.c3_value), Triple(R.id.c4, R.id.c4_label, R.id.c4_value),
            Triple(R.id.c5, R.id.c5_label, R.id.c5_value), Triple(R.id.c6, R.id.c6_label, R.id.c6_value),
        )
        private val rows = listOf(R.id.row1, R.id.row2, R.id.row3)

        private fun fillGrid(v: RemoteViews, list: List<Metric>) {
            cells.forEachIndexed { i, (cell, label, value) ->
                val m = list.getOrNull(i)
                // An empty right-hand cell stays as a spacer so its row keeps two columns.
                v.setViewVisibility(cell, if (m == null) View.INVISIBLE else View.VISIBLE)
                v.setTextViewText(label, m?.label ?: "")
                v.setTextViewText(value, m?.value ?: "")
            }
            rows.forEachIndexed { i, row ->
                v.setViewVisibility(row, if (list.size > i * 2) View.VISIBLE else View.GONE)
            }
            v.setViewVisibility(R.id.grid, if (list.isEmpty()) View.GONE else View.VISIBLE)
        }

        private fun unconfigured(ctx: Context, size: WidgetSize): RemoteViews =
            message(ctx, size, "Izberite postajo", "Pridržite pripomoček in izberite nastavitve.")

        private fun unavailable(ctx: Context, size: WidgetSize, name: String?): RemoteViews =
            message(ctx, size, name ?: "Postaja", "Podatki trenutno niso na voljo.")

        private fun message(ctx: Context, size: WidgetSize, title: String, body: String): RemoteViews {
            val v = RemoteViews(ctx.packageName, layoutFor(size))
            v.setImageViewBitmap(R.id.bg_image, gradient(null))
            v.setViewVisibility(R.id.scrim, View.GONE)
            v.setTextViewText(R.id.name, title)
            v.setTextViewText(R.id.temp, "–")
            v.setTextViewText(R.id.updated, body)
            when (size) {
                WidgetSize.SMALL -> fillLines(v, emptyList(), listOf(R.id.m1, R.id.m2))
                WidgetSize.MEDIUM -> {
                    fillLines(v, emptyList(), listOf(R.id.m1, R.id.m2, R.id.m3, R.id.m4))
                    v.setViewVisibility(R.id.metrics, View.GONE)
                }
                WidgetSize.LARGE -> fillGrid(v, emptyList())
            }
            return v
        }

        /** Background without a photo: the temperature colour fading into navy. */
        private fun gradient(temp: Double?): Bitmap {
            val bmp = Bitmap.createBitmap(120, 120, Bitmap.Config.ARGB_8888)
            val c = temperatureColor(temp)
            val top = (0xD9 shl 24) or (c and 0x00FFFFFF)
            val paint = Paint().apply {
                shader = LinearGradient(120f, 0f, 0f, 120f, top, 0xFF0E1726.toInt(), Shader.TileMode.CLAMP)
            }
            Canvas(bmp).drawRect(0f, 0f, 120f, 120f, paint)
            return bmp
        }

        private fun openApp(ctx: Context): PendingIntent = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
