package com.qlueconsulting.scriptflip.ui.teleprompter

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import com.qlueconsulting.scriptflip.ui.theme.PrimaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SurfaceDark
import com.qlueconsulting.scriptflip.ui.theme.TextMuted
import com.qlueconsulting.scriptflip.ui.theme.TextPrimary
import com.qlueconsulting.scriptflip.ui.theme.TextSecondary
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
    val scrollOffset by viewModel.scrollOffset.collectAsState()

    var showControls by remember { mutableStateOf(true) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = {
                        viewModel.togglePlayPause()
                    },
                    onDoubleTap = {
                        showControls = !showControls
                    }
                )
            }
            .pointerInput(Unit) {
                detectDragGestures { _, dragAmount ->
                    viewModel.updateOffset(-dragAmount.y)
                }
            }
    ) {
        // Text Content Container with Mirroring and Vertical Offset
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .graphicsLayer {
                    scaleX = if (isMirrored) -1f else 1f
                }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .offset { IntOffset(0, -scrollOffset.roundToInt() + 250) }
            ) {
                Text(
                    text = viewModel.script.cleanTeleprompterText,
                    fontSize = fontSize.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    lineHeight = (fontSize * 1.4f).sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(600.dp))
            }
        }

        // Top Header Controls
        if (showControls) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 40.dp, start = 16.dp, end = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = onClose,
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Color(0x88000000))
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close",
                        tint = Color.White
                    )
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Mirror button
                    IconButton(
                        onClick = { viewModel.toggleMirror() },
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape)
                            .background(if (isMirrored) PrimaryPurple else Color(0x88000000))
                    ) {
                        Icon(
                            imageVector = Icons.Default.Flip,
                            contentDescription = "Mirror Prompter",
                            tint = Color.White
                        )
                    }

                    // Reset button
                    IconButton(
                        onClick = { viewModel.reset() },
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape)
                            .background(Color(0x88000000))
                    ) {
                        Icon(
                            imageVector = Icons.Default.Replay,
                            contentDescription = "Rewind to Top",
                            tint = Color.White
                        )
                    }
                }
            }

            // Bottom Floating Controls Panel
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                shape = RoundedCornerShape(20.dp),
                color = Color(0xDD151A22)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    // Font Size Slider
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Size: ${fontSize.roundToInt()}pt",
                            fontSize = 12.sp,
                            color = TextSecondary,
                            modifier = Modifier.width(70.dp)
                        )
                        Slider(
                            value = fontSize,
                            onValueChange = { viewModel.setFontSize(it) },
                            valueRange = 18f..56f,
                            colors = SliderDefaults.colors(
                                thumbColor = AccentCyan,
                                activeTrackColor = AccentCyan
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }

                    // Speed Slider
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Speed: ${scrollSpeed.roundToInt()}",
                            fontSize = 12.sp,
                            color = TextSecondary,
                            modifier = Modifier.width(70.dp)
                        )
                        Slider(
                            value = scrollSpeed,
                            onValueChange = { viewModel.setScrollSpeed(it) },
                            valueRange = 15f..100f,
                            colors = SliderDefaults.colors(
                                thumbColor = PrimaryPurple,
                                activeTrackColor = PrimaryPurple
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }

                    // Play/Pause Fab and hint
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Tap screen to pause • Double tap to hide controls",
                            fontSize = 11.sp,
                            color = TextMuted
                        )

                        FloatingActionButton(
                            onClick = { viewModel.togglePlayPause() },
                            containerColor = PrimaryPurple,
                            contentColor = Color.White,
                            shape = CircleShape,
                            modifier = Modifier.size(48.dp)
                        ) {
                            Icon(
                                imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                contentDescription = if (isPlaying) "Pause" else "Play"
                            )
                        }
                    }
                }
            }
        }
    }
}
