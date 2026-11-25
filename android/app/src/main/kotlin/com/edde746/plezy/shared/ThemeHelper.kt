package com.edde746.plezy.shared

import android.graphics.Color

object ThemeHelper {
  fun themeColor(mode: String?): Int? = when (mode) {
    "oled" -> Color.BLACK
    "dark" -> Color.parseColor("#030B10")
    "light" -> Color.parseColor("#F1F8F7")
    else -> null
  }
}
