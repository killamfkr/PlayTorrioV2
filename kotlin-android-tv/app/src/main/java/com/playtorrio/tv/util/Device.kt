package com.playtorrio.tv.util

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration

fun Context.isTelevision(): Boolean {
    val uiMode = getSystemService(UiModeManager::class.java)
    if (uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
}
