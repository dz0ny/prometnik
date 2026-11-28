package dev.dz0ny.promet.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.Switch
import android.widget.TextView
import java.text.Normalizer
import java.util.concurrent.Executors

/**
 * Widget settings: which readings to show and which station. Opens when the
 * widget is added and again from the launcher's widget settings.
 */
class StationWidgetConfigActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var config: WidgetConfig
    private var all: List<StationReading> = emptyList()
    private lateinit var adapter: ArrayAdapter<String>
    private var shown: List<StationReading> = emptyList()
    private lateinit var status: TextView
    private lateinit var save: Button
    private lateinit var progress: ProgressBar

    private val navy = 0xFF0E1726.toInt()
    private val muted = 0xB3FFFFFF.toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Backing out must not leave an empty widget behind.
        setResult(RESULT_CANCELED)
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        config = WidgetConfig.load(this, widgetId)
        window.statusBarColor = navy
        window.navigationBarColor = navy
        setContentView(buildUi())
        loadStations()
    }

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private fun text(s: String, sizeSp: Float, color: Int = 0xFFFFFFFF.toInt(), bold: Boolean = false) =
        TextView(this).apply {
            text = s
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
        }

    private fun buildUi(): View {
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(8))
        }
        header.addView(text("Vremenska postaja", 24f, bold = true))
        header.addView(text("Kaj naj pripomoček prikazuje in s katere postaje.", 14f, muted).apply {
            setPadding(0, dp(4), 0, dp(16))
        })

        header.addView(section("Prikaži"))
        val toggles = listOf(
            Triple("Slika kamere", config.camera) { v: Boolean -> config = config.copy(camera = v) },
            Triple("Veter", config.wind) { v: Boolean -> config = config.copy(wind = v) },
            Triple("Padavine danes", config.rain) { v: Boolean -> config = config.copy(rain = v) },
            Triple("Najnižja in najvišja", config.minMax) { v: Boolean -> config = config.copy(minMax = v) },
            Triple("Vlaga", config.humidity) { v: Boolean -> config = config.copy(humidity = v) },
            Triple("Rosišče", config.dew) { v: Boolean -> config = config.copy(dew = v) },
            Triple("Zračni tlak", config.pressure) { v: Boolean -> config = config.copy(pressure = v) },
        )
        toggles.forEach { (label, on, set) ->
            header.addView(Switch(this).apply {
                text = label
                isChecked = on
                setTextColor(0xFFFFFFFF.toInt())
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                minHeight = dp(48)
                setOnCheckedChangeListener { _, v -> set(v) }
            })
        }

        status = text(selectedLabel(), 14f, muted).apply { setPadding(0, dp(12), 0, dp(8)) }
        save = Button(this).apply {
            text = "Shrani"
            isEnabled = config.stationId != null
            setOnClickListener { finishWith(config) }
        }
        header.addView(status)
        header.addView(save)

        header.addView(section("Postaja"))
        header.addView(EditText(this).apply {
            hint = "Išči postajo"
            setHintTextColor(muted)
            setTextColor(0xFFFFFFFF.toInt())
            setSingleLine()
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun afterTextChanged(s: Editable?) = filter(s?.toString() ?: "")
            })
        })
        progress = ProgressBar(this).apply { setPadding(0, dp(16), 0, dp(16)) }
        header.addView(progress)

        adapter = object : ArrayAdapter<String>(this, android.R.layout.simple_list_item_1, mutableListOf()) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                (super.getView(position, convertView, parent) as TextView).apply {
                    setTextColor(0xFFFFFFFF.toInt())
                    minHeight = dp(52)
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(20), 0, dp(20), 0)
                    val st = shown.getOrNull(position)
                    setTypeface(null, if (st?.id == config.stationId) Typeface.BOLD else Typeface.NORMAL)
                }
        }
        return ListView(this).apply {
            setBackgroundColor(navy)
            fitsSystemWindows = true
            addHeaderView(header, null, false)
            this.adapter = this@StationWidgetConfigActivity.adapter
            onItemClickListener = AdapterView.OnItemClickListener { _, _, pos, _ ->
                val st = shown.getOrNull(pos - headerViewsCount) ?: return@OnItemClickListener
                finishWith(config.copy(stationId = st.id, stationName = st.name))
            }
        }
    }

    private fun section(title: String) = text(title.uppercase(), 12f, 0xFF4FC3F7.toInt(), bold = true).apply {
        setPadding(0, dp(16), 0, dp(4))
        letterSpacing = 0.08f
    }

    private fun selectedLabel() = config.stationName?.let { "Izbrana postaja: $it" } ?: "Postaja še ni izbrana."

    private fun fold(s: String) =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()

    private fun filter(q: String) {
        val f = fold(q.trim())
        shown = if (f.isEmpty()) all else all.filter { fold(it.name).contains(f) }
        adapter.clear()
        adapter.addAll(shown.map { s -> s.temp?.let { "${s.name}   ${Fmt.degrees(it)}" } ?: s.name })
    }

    private fun loadStations() {
        Executors.newSingleThreadExecutor().execute {
            val list = runCatching { StationFeed.stations() }.getOrNull()
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                progress.visibility = View.GONE
                if (list == null) {
                    status.text = "Seznama postaj ni bilo mogoče naložiti. Preverite povezavo."
                } else {
                    all = list
                    filter("")
                }
            }
        }
    }

    private fun finishWith(c: WidgetConfig) {
        WidgetConfig.save(this, widgetId, c)
        StationWidgetProvider.refresh(this, intArrayOf(widgetId))
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }
}
