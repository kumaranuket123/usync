package com.crn.usync

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/// Shows the couple's shared drawing. The Dart side renders it to a PNG and
/// stores the path under `doodle_path`; this only displays that picture.
class DoodleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val path = widgetData.getString("doodle_path", null)
        val updated = widgetData.getString("doodle_updated", null)
        val bitmap = path?.let { File(it) }?.takeIf { it.exists() }
            ?.let { BitmapFactory.decodeFile(it.absolutePath) }

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_doodle).apply {
                if (bitmap != null) {
                    setImageViewBitmap(R.id.doodle_image, bitmap)
                    setViewVisibility(R.id.doodle_image, View.VISIBLE)
                    setViewVisibility(R.id.doodle_empty, View.GONE)
                } else {
                    setViewVisibility(R.id.doodle_image, View.GONE)
                    setViewVisibility(R.id.doodle_empty, View.VISIBLE)
                }
                setTextViewText(R.id.doodle_caption, updated ?: "Draw together")
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
