package com.qlueconsulting.scriptflip.ui.navigation

sealed class Screen(val route: String) {
    data object Generator : Screen("generator")
    data object Results : Screen("results")
    data object Teleprompter : Screen("teleprompter")
    data object Paywall : Screen("paywall")
    data object History : Screen("history")
    data object About : Screen("about")
}
