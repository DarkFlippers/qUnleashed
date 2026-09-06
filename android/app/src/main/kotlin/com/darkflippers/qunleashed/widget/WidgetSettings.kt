package com.darkflippers.qunleashed.widget

import android.content.Context

/**
 * Look settings as Dart last pushed them; see HomeWidgetSettings in
 * lib/services/home_widget/settings.dart for what each value means.
 */
data class WidgetSettings(
    val theme: String,
    val iconStyle: String,
    val border: String,
    val captionShown: Boolean,
    val captionSize: String,
) {
    companion object {
        private const val PREFS = "qunleashed_widget_settings"

        val DEFAULT = WidgetSettings(
            theme = "categories",
            iconStyle = "solid",
            border = "none",
            captionShown = true,
            captionSize = "normal",
        )

        fun load(context: Context): WidgetSettings {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return WidgetSettings(
                theme = p.getString("theme", DEFAULT.theme) ?: DEFAULT.theme,
                iconStyle = p.getString("iconStyle", DEFAULT.iconStyle) ?: DEFAULT.iconStyle,
                border = p.getString("border", DEFAULT.border) ?: DEFAULT.border,
                captionShown = p.getBoolean("captionShown", DEFAULT.captionShown),
                captionSize = p.getString("captionSize", DEFAULT.captionSize) ?: DEFAULT.captionSize,
            )
        }

        fun save(context: Context, arguments: Any?) {
            val map = arguments as? Map<*, *> ?: return
            val base = load(context)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("theme", map["theme"] as? String ?: base.theme)
                .putString("iconStyle", map["iconStyle"] as? String ?: base.iconStyle)
                .putString("border", map["border"] as? String ?: base.border)
                .putBoolean("captionShown", map["captionShown"] as? Boolean ?: base.captionShown)
                .putString("captionSize", map["captionSize"] as? String ?: base.captionSize)
                .apply()
        }
    }
}
