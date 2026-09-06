package com.darkflippers.qunleashed.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.darkflippers.qunleashed.R

/**
 * Draws a key widget: the category badge (a rounded square, as in the app)
 * and one caption — the key name, or whatever the tap is doing right now.
 * Three layouts by cell size; colors follow the chosen theme, which the
 * settings page previews with the same rules.
 */
object KeyWidgetRenderer {
    private const val WIDE_MIN_DP = 110
    private const val TALL_MIN_DP = 110

    private const val BADGE_SMALL_DP = 40
    private const val BADGE_WIDE_DP = 44
    private const val BADGE_LARGE_DP = 72

    fun update(context: Context, widgetId: Int) {
        val manager = AppWidgetManager.getInstance(context)
        manager.updateAppWidget(widgetId, render(context, manager, widgetId))
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, KeyWidgetProvider::class.java))
        for (id in ids) manager.updateAppWidget(id, render(context, manager, id))
    }

    fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val key = KeyWidgetStore.get(context, widgetId)
        val state = KeyWidgetStore.state(widgetId)
        val settings = WidgetSettings.load(context)
        val look = Look.resolve(context, settings, key)
        val options = manager.getAppWidgetOptions(widgetId)
        // The background is a bitmap cut to the cell, so every size the
        // launcher may show gets its own drawing.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!sizes.isNullOrEmpty()) {
                return RemoteViews(sizes.associateWith { build(context, it, widgetId, key, state, settings, look) })
            }
        }
        val fallback = SizeF(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).coerceAtLeast(40).toFloat(),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT).coerceAtLeast(40).toFloat(),
        )
        return build(context, fallback, widgetId, key, state, settings, look)
    }

    private fun layoutFor(size: SizeF): Pair<Int, Int> = when {
        size.width >= WIDE_MIN_DP && size.height >= TALL_MIN_DP -> R.layout.widget_key_large to BADGE_LARGE_DP
        size.width >= WIDE_MIN_DP -> R.layout.widget_key_wide to BADGE_WIDE_DP
        else -> R.layout.widget_key_small to BADGE_SMALL_DP
    }

    private fun build(
        context: Context,
        size: SizeF,
        widgetId: Int,
        key: WidgetKeyData?,
        state: String,
        settings: WidgetSettings,
        look: Look,
    ): RemoteViews {
        val (layout, badgeDp) = layoutFor(size)
        val views = RemoteViews(context.packageName, layout)

        views.setImageViewBitmap(R.id.widget_bg, background(context, size.width, size.height, settings, look))

        val icon = if (key == null) R.drawable.ic_widget_key else categoryIcon(key.category)
        views.setImageViewBitmap(R.id.widget_badge, badge(context, badgeDp, icon, look))

        val caption = if (key == null) context.getString(R.string.widget_choose_key) else caption(context, key, state)
        views.setTextViewText(R.id.widget_caption, caption)
        views.setTextColor(R.id.widget_caption, look.text)
        views.setTextViewTextSize(
            R.id.widget_caption,
            TypedValue.COMPLEX_UNIT_SP,
            captionSp(layout, settings.captionSize),
        )
        views.setViewVisibility(
            R.id.widget_caption,
            if (settings.captionShown || key == null) View.VISIBLE else View.GONE,
        )

        views.setOnClickPendingIntent(R.id.widget_root, tapIntent(context, widgetId))
        return views
    }

    /**
     * The widget background, drawn to the cell: a rounded rectangle with the
     * system widget radius, the theme surface, and the border just inside
     * the outline. One bitmap, because tinting a stroke-only drawable through
     * RemoteViews fills it instead.
     */
    private fun background(context: Context, wDp: Float, hDp: Float, settings: WidgetSettings, look: Look): Bitmap {
        val density = context.resources.displayMetrics.density
        val w = (wDp * density).toInt().coerceAtLeast(1)
        val h = (hDp * density).toInt().coerceAtLeast(1)
        val radius = context.resources.getDimension(R.dimen.widget_corner_radius)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val rect = RectF(0f, 0f, w.toFloat(), h.toFloat())
        canvas.drawRoundRect(rect, radius, radius, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = look.background })

        val border = look.border
        if (border != null) {
            val widthPx = (if (settings.border == "accent") 2f else 1f) * density
            val inset = widthPx / 2f
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = border
                style = Paint.Style.STROKE
                strokeWidth = widthPx
            }
            canvas.drawRoundRect(
                RectF(inset, inset, w - inset, h - inset),
                radius - inset,
                radius - inset,
                stroke,
            )
        }
        return bitmap
    }

    private fun captionSp(layout: Int, size: String): Float {
        val base = if (layout == R.layout.widget_key_small) 11f else 14f
        return when (size) {
            "small" -> base - 2f
            "large" -> base + 2f
            else -> base
        }
    }

    // The plate and the icon are one bitmap, centered exactly: a rounded
    // square as QIconBadge draws it in the app, or the bare icon.
    private fun badge(context: Context, dp: Int, icon: Int, look: Look): Bitmap {
        val density = context.resources.displayMetrics.density
        val px = (dp * density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val plate = look.plate
        if (plate != null) {
            val radius = px * 8f / 36f
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = plate }
            canvas.drawRoundRect(RectF(0f, 0f, px.toFloat(), px.toFloat()), radius, radius, paint)
        }
        val drawable = context.getDrawable(icon)?.mutate() ?: return bitmap
        val iconPx = (px * 24f / 36f).toInt()
        val inset = (px - iconPx) / 2
        drawable.setBounds(inset, inset, inset + iconPx, inset + iconPx)
        drawable.setTint(look.icon)
        drawable.draw(canvas)
        return bitmap
    }

    private fun caption(context: Context, key: WidgetKeyData, state: String): String = when (state) {
        "connecting" -> context.getString(R.string.widget_state_connecting)
        "emulating" -> context.getString(R.string.widget_state_emulating)
        "sending" -> context.getString(R.string.widget_state_sending)
        "sent" -> context.getString(R.string.widget_state_sent)
        "errorNoDevice" -> context.getString(R.string.widget_error_no_device)
        "errorBusy" -> context.getString(R.string.widget_error_busy)
        "errorFile" -> context.getString(R.string.widget_error_file)
        "errorFailed" -> context.getString(R.string.widget_error_failed)
        else -> key.name
    }

    private fun tapIntent(context: Context, widgetId: Int): PendingIntent {
        val intent = Intent(context, KeyWidgetReceiver::class.java)
            .setAction(KeyWidgetReceiver.ACTION_TAP)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        return PendingIntent.getBroadcast(
            context,
            widgetId,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun isNight(context: Context): Boolean =
        context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES

    // Same values as ArchiveCategoryColor in lib/theme/colors/category.dart.
    fun categoryColor(category: String?): Int = when (category) {
        "nfc" -> 0xFF34C7A4.toInt()
        "rfid" -> 0xFF5856D6.toInt()
        "ibutton" -> 0xFF007AFF.toInt()
        "infrared" -> 0xFFAF52DE.toInt()
        "subghz" -> 0xFFFF9B34.toInt()
        "wardriving" -> 0xFF64D2FF.toInt()
        "badusb" -> 0xFFFF3B30.toInt()
        "javascript" -> 0xFFE7AF17.toInt()
        else -> 0xFF9E9E9E.toInt()
    }

    private fun categoryIcon(category: String): Int = when (category) {
        "nfc" -> R.drawable.ic_widget_nfc
        "rfid" -> R.drawable.ic_widget_rfid
        "ibutton" -> R.drawable.ic_widget_ibutton
        "subghz", "wardriving" -> R.drawable.ic_widget_sub
        else -> R.drawable.ic_widget_key
    }

    /**
     * Resolved colors of one widget; the same rules as `_Look` on the
     * settings page. Every theme takes light or dark from the phone:
     * `categories` is the app's own surfaces with the category color;
     * `system` is the firmware look — dark Unleashed at night, light OFW by
     * day; `material` is the phone's Material You colors throughout.
     */
    class Look(
        val background: Int,
        val text: Int,
        val plate: Int?,
        val icon: Int,
        val border: Int?,
    ) {
        companion object {
            private const val LIGHT_BACKGROUND = 0xFFFFFFFF.toInt()
            private const val DARK_BACKGROUND = 0xFF151515.toInt()
            private const val LIGHT_TEXT = 0xFF000000.toInt()
            private const val DARK_TEXT = 0xFFFFFFFF.toInt()
            private const val LIGHT_BORDER = 0xFFDFDFDF.toInt()
            private const val DARK_BORDER = 0xFF2C2C2C.toInt()
            private const val MUTED = 0xFF9E9E9E.toInt()

            // Primary colors of the firmwares in lib/components/config.dart.
            private const val UNLEASHED = 0xFFCC241D.toInt()
            private const val OFW = 0xFFFF8200.toInt()

            fun resolve(context: Context, s: WidgetSettings, key: WidgetKeyData?): Look {
                val dark = isNight(context)
                val palette = MaterialPalette.of(context)
                if (s.theme == "material" && palette != null) {
                    return material(palette, dark, s, key)
                }
                val background = if (dark) DARK_BACKGROUND else LIGHT_BACKGROUND
                val text = if (dark) DARK_TEXT else LIGHT_TEXT
                val color = when {
                    key == null -> MUTED
                    s.theme == "system" -> if (dark) UNLEASHED else OFW
                    else -> categoryColor(key.category)
                }
                val plate = when (s.iconStyle) {
                    "tinted" -> withAlpha(color, 0.18f)
                    "plain" -> null
                    else -> color
                }
                val icon = if (s.iconStyle == "solid") Color.WHITE else color
                val border = when (s.border) {
                    "thin" -> if (dark) DARK_BORDER else LIGHT_BORDER
                    "accent" -> color
                    else -> null
                }
                return Look(background, text, plate, icon, border)
            }

            // The widget as one more themed icon on the home screen: the
            // launcher's icon background and icon color, the solid plate
            // inverted the way the launcher inverts an icon without a
            // monochrome layer.
            private fun material(p: MaterialPalette, dark: Boolean, s: WidgetSettings, key: WidgetKeyData?): Look {
                val background = if (dark) p.backgroundDark else p.backgroundLight
                val foreground = if (dark) p.foregroundDark else p.foregroundLight
                val plate = when (s.iconStyle) {
                    "tinted" -> withAlpha(foreground, 0.18f)
                    "plain" -> null
                    else -> foreground
                }
                val icon = if (s.iconStyle == "solid") background else foreground
                val border = when (s.border) {
                    "thin" -> withAlpha(foreground, 0.35f)
                    "accent" -> foreground
                    else -> null
                }
                return Look(background, foreground, plate, icon, border)
            }

            private fun withAlpha(color: Int, alpha: Float): Int =
                Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))
        }
    }
}

/**
 * The colors the launcher paints themed icons with (Launcher3's
 * `themed_icon_background_color` / `themed_icon_color`), on Android 12+.
 */
class MaterialPalette(
    val backgroundLight: Int,
    val backgroundDark: Int,
    val foregroundLight: Int,
    val foregroundDark: Int,
) {
    fun toMap(): Map<String, Int> = mapOf(
        "backgroundLight" to backgroundLight,
        "backgroundDark" to backgroundDark,
        "foregroundLight" to foregroundLight,
        "foregroundDark" to foregroundDark,
    )

    companion object {
        fun of(context: Context): MaterialPalette? {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
            return MaterialPalette(
                backgroundLight = context.getColor(android.R.color.system_accent1_100),
                backgroundDark = context.getColor(android.R.color.system_accent1_800),
                foregroundLight = context.getColor(android.R.color.system_accent1_700),
                foregroundDark = context.getColor(android.R.color.system_accent1_200),
            )
        }
    }
}
