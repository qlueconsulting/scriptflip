package com.qlueconsulting.scriptflip.ui.splash

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.R
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Animated splash loading screen matching iOS SplashScreenView that transitions
 * smoothly to the main UI.
 */
@Composable
fun SplashScreenView(
    content: @Composable () -> Unit
) {
    var isSplashActive by remember { mutableStateOf(true) }
    val logoScale = remember { Animatable(0.8f) }
    val logoAlpha = remember { Animatable(0f) }
    val textAlpha = remember { Animatable(0f) }

    LaunchedEffect(Unit) {
        // Animate logo scale and opacity
        launch {
            logoScale.animateTo(
                targetValue = 1.0f,
                animationSpec = tween(durationMillis = 650, easing = LinearOutSlowInEasing)
            )
        }
        launch {
            logoAlpha.animateTo(
                targetValue = 1.0f,
                animationSpec = tween(durationMillis = 600, easing = LinearOutSlowInEasing)
            )
        }

        // Animate text opacity with slight delay
        delay(200)
        launch {
            textAlpha.animateTo(
                targetValue = 1.0f,
                animationSpec = tween(durationMillis = 700, easing = FastOutSlowInEasing)
            )
        }

        // Hold splash screen to complete animation then transition smoothly
        delay(1800)
        isSplashActive = false
    }

    Box(modifier = Modifier.fillMaxSize()) {
        content()

        AnimatedVisibility(
            visible = isSplashActive,
            enter = fadeIn(),
            exit = fadeOut(animationSpec = tween(durationMillis = 400)) + scaleOut(
                targetScale = 1.05f,
                animationSpec = tween(durationMillis = 400)
            )
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0xFF0A0A0F)),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Spacer(modifier = Modifier.weight(1f))

                    // Logo with ambient cyan glow
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .scale(logoScale.value)
                            .alpha(logoAlpha.value)
                    ) {
                        // Ambient cyan glow background
                        Box(
                            modifier = Modifier
                                .size(180.dp, 110.dp)
                                .background(
                                    brush = Brush.radialGradient(
                                        colors = listOf(
                                            Color(0x6600E5FF),
                                            Color(0x2200E5FF),
                                            Color.Transparent
                                        )
                                    ),
                                    shape = CircleShape
                                )
                        )

                        Image(
                            painter = painterResource(id = R.drawable.ic_scriptflip_logo),
                            contentDescription = "ScriptFlip Logo",
                            contentScale = ContentScale.Fit,
                            modifier = Modifier
                                .widthIn(max = 280.dp)
                                .height(140.dp)
                                .clip(RoundedCornerShape(16.dp))
                        )
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // App Title & Tagline
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.alpha(textAlpha.value)
                    ) {
                        Text(
                            text = "ScriptFlip",
                            fontSize = 38.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = FontFamily.SansSerif,
                            color = Color.White,
                            textAlign = TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(8.dp))

                        Text(
                            text = "Viral Short-Form Scripts in Seconds",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            style = TextStyle(
                                brush = Brush.horizontalGradient(
                                    colors = listOf(
                                        Color(0xFF00E5FF),
                                        Color(0xFF00E699)
                                    )
                                )
                            ),
                            letterSpacing = 0.5.sp,
                            textAlign = TextAlign.Center
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    // Subtle loading indicator
                    CircularProgressIndicator(
                        modifier = Modifier
                            .size(26.dp)
                            .alpha(textAlpha.value),
                        color = AccentCyan,
                        strokeWidth = 2.5.dp
                    )

                    Spacer(modifier = Modifier.height(36.dp))
                }
            }
        }
    }
}
