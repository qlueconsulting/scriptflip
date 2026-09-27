package com.qlueconsulting.scriptflip.ui.teleprompter

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun TeleprompterScreen(
    viewModel: TeleprompterViewModel,
    onClose: () -> Unit
) {
    val isPlaying by viewModel.isPlaying.collectAsState()
    val scrollSpeed by viewModel.scrollSpeed.collectAsState()
    val fontSize by viewModel.fontSize.collectAsState()
    val isMirrored by viewModel.isMirrored.collectAsState()

    val scrollState = rememberScrollState()
    var showControls by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()

    // Smooth V-SYNC 60fps auto-scroll engine
    LaunchedEffect(isPlaying, scrollSpeed) {
        if (isPlaying) {
            var lastTime = withFrameNanos { it }
            while (isActive && isPlaying) {
                withFrameNanos { now ->
                    val deltaSec = (now - lastTime) / 1_000_000_000f
                    lastTime = now
                    // Scale scroll speed for comfortable reading rate
                    val pxToScroll = scrollSpeed * 2.2f * deltaSec
                    scrollState.dispatchRawDelta(pxToScroll)

                    if (scrollState.value >= scrollState.maxValue && scrollState.maxValue > 0) {
                        viewModel.pause()
                    }
                }
            }
        }
    }

    // Auto-hide controls 3 seconds after starting playback
    LaunchedEffect(isPlaying) {
        if (isPlaying) {
            delay(3000)
            showControls = false
        } else {
            showControls = true
        }
    }

    // Calculate dynamic countdown timer
    val remainingPx = maxOf(0, scrollState.maxValue - scrollState.value)
    val speedPxPerSec = maxOf(10f, scrollSpeed * 2.2f)
    val remainingSec = (remainingPx / speedPxPerSec).roundToInt()
    val minutes = remainingSec / 60
    val seconds = remainingSec % 60
    val countdownString = String.format("%02d:%02d", minutes, seconds)

    // Split text into distinct paragraphs to guarantee unconstrained rendering
    val paragraphs = remember(viewModel.script.cleanTeleprompterText) {
        viewModel.script.cleanTeleprompterText
            .split("\n\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures {
                    showControls = !showControls
                }
            }
    ) {
        val screenHeight = maxHeight

        // 1. Spoken Script Text Content with Native Compose Vertical Scroll (Full unconstrained height)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp)
                .graphicsLayer {
                    scaleX = if (isMirrored) -1f else 1f
                }
                .verticalScroll(scrollState)
        ) {
            // Top Spacer: Aligns the start of the script directly with the Reading Focus Guide Line (~32% screen height)
            Spacer(modifier = Modifier.height(screenHeight * 0.32f))

            // Title header
            if (viewModel.script.title.isNotBlank()) {
                Text(
                    text = viewModel.script.title,
                    fontSize = (fontSize * 0.55f).sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.45f),
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(18.dp))
            }

            // Render each paragraph individually: guarantees 100% of all paragraphs are measured and rendered
            paragraphs.forEachIndexed { index, paragraph ->
                Text(
                    text = paragraph,
                    fontSize = fontSize.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    lineHeight = (fontSize * 1.45f).sp,
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth()
                )
                if (index < paragraphs.lastIndex) {
                    Spacer(modifier = Modifier.height((fontSize * 0.9f).dp))
                }
            }

            // Generous Bottom Spacer: Allows the final paragraph to scroll all the way past the reading line
            Spacer(modifier = Modifier.height(screenHeight * 0.85f))
        }

        // 2. Reading Focus Guide Line with Inward Indicator Arrows (Fixed at 32% screen height)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = if (isMirrored) -1f else 1f
                }
        ) {
            Spacer(modifier = Modifier.height(screenHeight * 0.32f))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp)
            ) {
                // Soft yellow glow background bar
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(fontSize.dp * 1.35f)
                        .background(Color(0xFFFFD54F).copy(alpha = 0.08f))
                )

                // High-visibility focus line with inward indicator arrows
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.Center),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        tint = Color(0xFFFFD54F),
                        modifier = Modifier.size(16.dp)
                    )

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(2.dp)
                            .padding(horizontal = 6.dp)
                            .background(Color(0xFFFFD54F).copy(alpha = 0.45f))
                    )

                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = null,
                        tint = Color(0xFFFFD54F),
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }

        // 3. Top Header Bar (No overlapping: Done on left, Timer in center, Mirror/Rewind on right)
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 44.dp, start = 16.dp, end = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Done Button (Left)
                Row(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color(0xCC1A1F2B))
                        .clickable(onClick = onClose)
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Done",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Done",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }

                // Countdown Timer (Center)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color(0xCC1A1F2B))
                        .border(1.dp, Color(0xFFFFD54F).copy(alpha = 0.4f), CircleShape)
                        .padding(horizontal = 12.dp, vertical = 7.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.AccessTime,
                        contentDescription = null,
                        tint = Color(0xFFFFD54F),
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = countdownString,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White
                    )
                }

                // Action Buttons: Mirror & Rewind (Right)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Mirror flip button
                    IconButton(
                        onClick = { viewModel.toggleMirror() },
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(if (isMirrored) Color(0xFFFFD54F) else Color(0xCC1A1F2B))
                    ) {
                        Icon(
                            imageVector = Icons.Default.Flip,
                            contentDescription = "Mirror Prompter",
                            tint = if (isMirrored) Color.Black else Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    }

                    // Rewind to top button
                    IconButton(
                        onClick = {
                            scope.launch {
                                viewModel.pause()
                                scrollState.scrollTo(0)
                            }
                        },
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(Color(0xCC1A1F2B))
                    ) {
                        Icon(
                            imageVector = Icons.Default.Replay,
                            contentDescription = "Rewind to Top",
                            tint = Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }

        // 4. Sleek Floating Bottom Control Bar (Auto-hides during playback)
        AnimatedVisibility(
            visible = showControls,
            modifier = Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 20.dp),
                shape = RoundedCornerShape(24.dp),
                color = Color(0xF0181E29),
                border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.12f))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // Left: Font Size Slider
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Default.FormatSize,
                                    contentDescription = null,
                                    tint = AccentCyan,
                                    modifier = Modifier.size(13.dp)
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(text = "Size", fontSize = 11.sp, color = Color.Gray, fontWeight = FontWeight.Bold)
                            }
                            Text(
                                text = "${fontSize.roundToInt()}pt",
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                color = AccentCyan
                            )
                        }
                        Slider(
                            value = fontSize,
                            onValueChange = { viewModel.setFontSize(it) },
                            valueRange = 20f..52f,
                            colors = SliderDefaults.colors(
                                thumbColor = AccentCyan,
                                activeTrackColor = AccentCyan,
                                inactiveTrackColor = Color.DarkGray
                            )
                        )
                    }

                    // Center: Play / Pause Button
                    FloatingActionButton(
                        onClick = {
                            viewModel.togglePlayPause()
                        },
                        containerColor = if (isPlaying) Color(0xFFFFD54F) else AccentCyan,
                        contentColor = Color.Black,
                        shape = CircleShape,
                        modifier = Modifier.size(54.dp)
                    ) {
                        Icon(
                            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = if (isPlaying) "Pause" else "Play",
                            modifier = Modifier.size(28.dp)
                        )
                    }

                    // Right: Scroll Speed Slider
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Default.Speed,
                                    contentDescription = null,
                                    tint = Color(0xFFFFD54F),
                                    modifier = Modifier.size(13.dp)
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(text = "Speed", fontSize = 11.sp, color = Color.Gray, fontWeight = FontWeight.Bold)
                            }
                            Text(
                                text = "${scrollSpeed.roundToInt()}",
                                fontSize = 11.sp,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFFFFD54F)
                            )
                        }
                        Slider(
                            value = scrollSpeed,
                            onValueChange = { viewModel.setScrollSpeed(it) },
                            valueRange = 10f..100f,
                            colors = SliderDefaults.colors(
                                thumbColor = Color(0xFFFFD54F),
                                activeTrackColor = Color(0xFFFFD54F),
                                inactiveTrackColor = Color.DarkGray
                            )
                        )
                    }
                }
            }
        }
    }
}
