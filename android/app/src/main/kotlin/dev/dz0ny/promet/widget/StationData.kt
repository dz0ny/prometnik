package dev.dz0ny.promet.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.Collator
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

/** One station reading from the ceste.si feed the app uses. */
data class StationReading(
    val id: Int,
    val name: String,
    val cameraLink: String,
    val timestamp: Long?,
    val temp: Double?,
    val minTemp: Double?,
    val maxTemp: Double?,
    val humidity: Int?,
    val windDir: String?,
    val wind: Double?,
    val gust: Double?,
    val rain: Double?,
    val dew: Double?,
    val pressure: Int?,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("stationId", id)
        put("name", name)
        put("cameraLink", cameraLink)
        put("ts", timestamp ?: JSONObject.NULL)
        put("weather", JSONObject().apply {
            put("outdoorTemperatureC", temp ?: JSONObject.NULL)
            put("minOutdoorTemperatureC", minTemp ?: JSONObject.NULL)
            put("maxOutdoorTemperatureC", maxTemp ?: JSONObject.NULL)
            put("humidityPercentage", humidity ?: JSONObject.NULL)
            put("windDirection", windDir ?: JSONObject.NULL)
            put("windSpeedKmh", wind ?: JSONObject.NULL)
            put("windGustKmh", gust ?: JSONObject.NULL)
            put("dailyRainMm", rain ?: JSONObject.NULL)
            put("dewPointC", dew ?: JSONObject.NULL)
            put("pressureHpa", pressure ?: JSONObject.NULL)
        })
    }

    companion object {
        private val timeParser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
            // The feed's times carry no zone: they are Slovenian time.
            timeZone = TimeZone.getTimeZone("Europe/Ljubljana")
        }

        /** A feed record, or null for a station without weather. */
        fun parse(j: JSONObject, cachedTs: Boolean = false): StationReading? {
            val w = j.optJSONObject("weather") ?: return null
            fun d(k: String): Double? = if (w.isNull(k)) null else w.optDouble(k).takeUnless { it.isNaN() }
            fun i(k: String): Int? = if (w.isNull(k)) null else w.optInt(k)
            val ts = if (cachedTs) {
                if (j.isNull("ts")) null else j.optLong("ts")
            } else {
                w.optString("timestamp").takeIf { it.isNotEmpty() }?.let {
                    runCatching { timeParser.parse(it)?.time }.getOrNull()
                }
            }
            // The feed sends 0 % humidity when the sensor has no value.
            val hum = i("humidityPercentage")?.takeIf { it > 0 }
            return StationReading(
                id = j.optInt("stationId"),
                name = j.optString("name").trim().ifEmpty { "Postaja" },
                // Some stations list several cameras joined with ';': the first.
                cameraLink = j.optString("cameraLink").split(';').map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: "",
                timestamp = ts,
                temp = d("outdoorTemperatureC"),
                minTemp = d("minOutdoorTemperatureC"),
                maxTemp = d("maxOutdoorTemperatureC"),
                humidity = hum,
                windDir = if (w.isNull("windDirection")) null else w.optString("windDirection").trim().ifEmpty { null },
                wind = d("windSpeedKmh"),
                gust = d("windGustKmh"),
                rain = d("dailyRainMm"),
                dew = d("dewPointC"),
                pressure = i("pressureHpa")?.takeIf { it > 0 },
            )
        }
    }
}

object StationFeed {
    private const val ENDPOINT = "https://www.ceste.si/Vremenske/Vreme/KamereInVreme"
    private const val PROXY_HOST = "prometnik-cams.dz0ny.workers.dev"
    private val proxiedHosts = setOf("kamere.dars.si", "www.drsc.si", "drsc.si", "meteo.arso.gov.si")

    @Volatile private var cached: Pair<Long, List<StationReading>>? = null

    /** Every station that reports weather, sorted by name (Slovenian order). */
    fun stations(): List<StationReading> {
        cached?.let { if (System.currentTimeMillis() - it.first < 5 * 60_000) return it.second }
        val body = get(ENDPOINT)?.toString(Charsets.UTF_8) ?: throw java.io.IOException("feed")
        val arr = JSONArray(body)
        val out = (0 until arr.length()).mapNotNull { arr.optJSONObject(it)?.let(StationReading::parse) }
        val collator = Collator.getInstance(Locale("sl", "SI"))
        val sorted = out.sortedWith { a, b -> collator.compare(a.name, b.name) }
        cached = System.currentTimeMillis() to sorted
        return sorted
    }

    private fun get(url: String, timeoutMs: Int = 8000): ByteArray? {
        val c = URL(url).openConnection() as HttpURLConnection
        return try {
            c.connectTimeout = timeoutMs
            c.readTimeout = timeoutMs
            c.setRequestProperty("Accept", "application/json, image/*")
            c.setRequestProperty("User-Agent", "promet-android-widget/1.0 (+https://www.ceste.si/Vreme/)")
            if (c.responseCode != 200) null else c.inputStream.use { it.readBytes() }
        } finally {
            c.disconnect()
        }
    }

    /** The camera URL through the app's edge cache (https, cached a minute). */
    fun cameraUrl(link: String): String? {
        if (link.isEmpty()) return null
        val uri = Uri.parse(link)
        val host = uri.host?.lowercase() ?: return null
        if (host !in proxiedHosts) return link
        val cleaned = uri.buildUpon().clearQuery().apply {
            uri.queryParameterNames.filter { it != "t" }.forEach { n ->
                uri.getQueryParameters(n).forEach { v -> appendQueryParameter(n, v) }
            }
        }.build().toString()
        val bucket = System.currentTimeMillis() / 300_000 * 300
        return Uri.Builder().scheme("https").authority(PROXY_HOST).path("/cam")
            .appendQueryParameter("u", cleaned)
            .appendQueryParameter("t", bucket.toString())
            .build().toString()
    }

    /** The camera frame scaled to at most [maxPx] wide (widget bitmaps are size-limited). */
    fun cameraBitmap(link: String, maxPx: Int = 640): Bitmap? = runCatching {
        val bytes = get(cameraUrl(link) ?: return null, 10_000) ?: return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxPx) sample *= 2
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        if (bmp.width <= maxPx) bmp
        else Bitmap.createScaledBitmap(bmp, maxPx, (bmp.height * maxPx.toFloat() / bmp.width).roundToInt(), true)
    }.getOrNull()

    // --- last good reading per station, for when the feed can't be reached ---

    private fun readingFile(ctx: Context, id: Int) = File(ctx.cacheDir, "widget-station-$id.json")
    fun imageFile(ctx: Context, id: Int) = File(ctx.cacheDir, "widget-station-$id.jpg")

    fun save(ctx: Context, r: StationReading, image: Bitmap?) {
        runCatching { readingFile(ctx, r.id).writeText(r.toJson().toString()) }
        if (image != null) runCatching {
            FileOutputStream(imageFile(ctx, r.id)).use { image.compress(Bitmap.CompressFormat.JPEG, 82, it) }
        }
    }

    fun loadReading(ctx: Context, id: Int): StationReading? = runCatching {
        StationReading.parse(JSONObject(readingFile(ctx, id).readText()), cachedTs = true)
    }.getOrNull()

    fun loadImage(ctx: Context, id: Int): Bitmap? =
        imageFile(ctx, id).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
}

/** The app's formatting rules (WeatherFormat in lib/widgets/weather_details.dart). */
object Fmt {
    fun decimal(v: Double, digits: Int = 1): String {
        var s = String.format(Locale.US, "%.${digits}f", v)
        if (s.toDouble() == 0.0) s = String.format(Locale.US, "%.${digits}f", 0.0)
        return s.replace('.', ',')
    }

    fun temp(c: Double?) = c?.let { "${decimal(it)} °C" } ?: "–"
    fun degrees(c: Double?) = c?.let { "${decimal(it)}°" } ?: "–"

    fun compass(dir: String?): String {
        val map = mapOf('N' to 'S', 'E' to 'V', 'S' to 'J', 'W' to 'Z')
        return dir?.uppercase()?.map { map[it] ?: it }?.joinToString("") ?: ""
    }

    fun wind(r: StationReading, withGust: Boolean): String {
        val w = r.wind ?: return "–"
        // No direction for calm air.
        val dir = if (w < 1) "" else compass(r.windDir)
        val gust = if (withGust && r.gust != null) " · sunki ${r.gust.roundToInt()}" else ""
        return "${w.roundToInt()} km/h" + (if (dir.isEmpty()) "" else " $dir") + gust
    }

    private val timeFmt = SimpleDateFormat("HH:mm", Locale("sl", "SI")).apply {
        timeZone = TimeZone.getTimeZone("Europe/Ljubljana")
    }

    fun time(ms: Long?) = ms?.let { timeFmt.format(java.util.Date(it)) } ?: "–"
}
