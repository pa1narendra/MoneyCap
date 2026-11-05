package com.moneycap.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: this month's spend and income. Values are written by
 * lib/services/widget_service.dart (totals only, never merchants or SMS text).
 */
class MoneyCapWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.moneycap_widget).apply {
                setTextViewText(R.id.widget_month, widgetData.getString("month", "This month"))
                setTextViewText(R.id.widget_spent, widgetData.getString("spent", "—"))
                setTextViewText(R.id.widget_income, widgetData.getString("income", "—"))
                setTextViewText(
                    R.id.widget_updated,
                    widgetData.getString("updated", "Open MoneyCap to sync"),
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
