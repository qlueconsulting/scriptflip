package com.qlueconsulting.scriptflip

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.qlueconsulting.scriptflip.ui.about.AboutScreen
import com.qlueconsulting.scriptflip.ui.generator.ScriptGeneratorScreen
import com.qlueconsulting.scriptflip.ui.generator.ScriptGeneratorViewModel
import com.qlueconsulting.scriptflip.ui.history.HistoryScreen
import com.qlueconsulting.scriptflip.ui.navigation.Screen
import com.qlueconsulting.scriptflip.ui.paywall.PaywallScreen
import com.qlueconsulting.scriptflip.ui.results.ScriptResultsScreen
import com.qlueconsulting.scriptflip.ui.splash.SplashScreenView
import com.qlueconsulting.scriptflip.ui.teleprompter.TeleprompterScreen
import com.qlueconsulting.scriptflip.ui.teleprompter.TeleprompterViewModel
import com.qlueconsulting.scriptflip.ui.theme.ScriptFlipTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ScriptFlipTheme {
                SplashScreenView {
                    val navController = rememberNavController()
                    val generatorViewModel: ScriptGeneratorViewModel = viewModel()

                    NavHost(
                        navController = navController,
                        startDestination = Screen.Generator.route
                    ) {
                        composable(Screen.Generator.route) {
                        ScriptGeneratorScreen(
                            viewModel = generatorViewModel,
                            onNavigateToResults = {
                                navController.navigate(Screen.Results.route)
                            },
                            onNavigateToHistory = {
                                navController.navigate(Screen.History.route)
                            },
                            onNavigateToAbout = {
                                navController.navigate(Screen.About.route)
                            },
                            onNavigateToPaywall = {
                                navController.navigate(Screen.Paywall.route)
                            }
                        )
                    }

                    composable(Screen.Results.route) {
                        ScriptResultsScreen(
                            viewModel = generatorViewModel,
                            onNavigateBack = {
                                navController.popBackStack()
                            },
                            onLaunchTeleprompter = { script ->
                                navController.navigate(Screen.Teleprompter.route)
                            }
                        )
                    }

                    composable(Screen.Teleprompter.route) {
                        val currentScript = generatorViewModel.currentScript.value
                        if (currentScript != null) {
                            val teleprompterViewModel = remember(currentScript) {
                                TeleprompterViewModel(currentScript)
                            }
                            TeleprompterScreen(
                                viewModel = teleprompterViewModel,
                                onClose = {
                                    navController.popBackStack()
                                }
                            )
                        } else {
                            navController.popBackStack()
                        }
                    }

                    composable(Screen.Paywall.route) {
                        PaywallScreen(
                            subscriptionManager = generatorViewModel.subscriptionManager,
                            onClose = {
                                navController.popBackStack()
                            }
                        )
                    }

                    composable(Screen.History.route) {
                        HistoryScreen(
                            viewModel = generatorViewModel,
                            onNavigateBack = {
                                navController.popBackStack()
                            },
                            onSelectScript = { script ->
                                navController.navigate(Screen.Results.route)
                            }
                        )
                    }

                    composable(Screen.About.route) {
                        AboutScreen(
                            viewModel = generatorViewModel,
                            onNavigateBack = {
                                navController.popBackStack()
                            }
                        )
                    }
                }
            }
        }
    }
}
}
