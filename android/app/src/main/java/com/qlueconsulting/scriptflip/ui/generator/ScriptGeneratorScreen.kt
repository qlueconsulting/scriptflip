package com.qlueconsulting.scriptflip.ui.generator

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.R
import com.qlueconsulting.scriptflip.data.model.Script
import com.qlueconsulting.scriptflip.data.model.ScriptStyle
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import com.qlueconsulting.scriptflip.ui.theme.AccentOrange
import com.qlueconsulting.scriptflip.ui.theme.BgDark
import com.qlueconsulting.scriptflip.ui.theme.CardBorder
import com.qlueconsulting.scriptflip.ui.theme.PrimaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SecondaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SurfaceDark
import com.qlueconsulting.scriptflip.ui.theme.SurfaceVariantDark
import com.qlueconsulting.scriptflip.ui.theme.TextMuted
import com.qlueconsulting.scriptflip.ui.theme.TextPrimary
import com.qlueconsulting.scriptflip.ui.theme.TextSecondary

@Composable
fun ScriptGeneratorScreen(
    viewModel: ScriptGeneratorViewModel,
    onNavigateToResults: () -> Unit,
    onNavigateToHistory: () -> Unit,
    onNavigateToAbout: () -> Unit,
    onNavigateToPaywall: () -> Unit
) {
    val inputText by viewModel.inputText.collectAsState()
    val selectedStyle by viewModel.selectedStyle.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val usage by viewModel.usage.collectAsState()
    val activeTier by viewModel.subscriptionManager.activeTier.collectAsState()
    val showPaywall by viewModel.showPaywall.collectAsState()

    if (showPaywall) {
        viewModel.dismissPaywall()
        onNavigateToPaywall()
    }

    Scaffold(
        containerColor = BgDark,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_scriptflip_mark),
                        contentDescription = "ScriptFlip Logo Mark",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .size(32.dp)
                            .clip(RoundedCornerShape(8.dp))
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Script",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Text(
                        text = "Flip",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        color = SecondaryPurple
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Quota Badge
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(SurfaceVariantDark)
                            .border(1.dp, if (activeTier.isPro) SecondaryPurple else CardBorder, RoundedCornerShape(12.dp))
                            .clickable { onNavigateToPaywall() }
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                    ) {
                        Text(
                            text = usage.badgeQuotaString(activeTier),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (activeTier.isPro) AccentCyan else TextSecondary
                        )
                    }

                    Spacer(modifier = Modifier.width(4.dp))

                    IconButton(onClick = onNavigateToHistory) {
                        Icon(
                            imageVector = Icons.Default.History,
                            contentDescription = "History",
                            tint = TextSecondary
                        )
                    }

                    IconButton(onClick = onNavigateToAbout) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = "About",
                            tint = TextSecondary
                        )
                    }
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            // Header card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceDark),
                border = androidx.compose.foundation.BorderStroke(1.dp, CardBorder)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Transform Ideas into Viral Scripts",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = "Paste a TikTok/Reels link, YouTube URL, or rough bullet notes below.",
                        fontSize = 14.sp,
                        color = TextSecondary
                    )
                }
            }

            // Input TextField
            OutlinedTextField(
                value = inputText,
                onValueChange = { viewModel.setInputText(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(160.dp),
                placeholder = {
                    Text(
                        text = "e.g. https://www.tiktok.com/@creator/video/123456\nor paste talking points & raw notes...",
                        color = TextMuted,
                        fontSize = 14.sp
                    )
                },
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = SurfaceDark,
                    unfocusedContainerColor = SurfaceDark,
                    focusedBorderColor = PrimaryPurple,
                    unfocusedBorderColor = CardBorder,
                    focusedTextColor = TextPrimary,
                    unfocusedTextColor = TextPrimary
                )
            )

            // Style Selector Header
            Text(
                text = "Tone & Creator Style",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary
            )

            // Vertical list of styles (no horizontal scrolling required)
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                ScriptStyle.entries.forEach { style ->
                    val isSelected = style == selectedStyle
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { viewModel.setSelectedStyle(style) },
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = if (isSelected) SurfaceVariantDark else SurfaceDark
                        ),
                        border = androidx.compose.foundation.BorderStroke(
                            width = if (isSelected) 2.dp else 1.dp,
                            color = if (isSelected) PrimaryPurple else CardBorder
                        )
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            // Radio indicator
                            Box(
                                modifier = Modifier
                                    .size(20.dp)
                                    .clip(androidx.compose.foundation.shape.CircleShape)
                                    .border(
                                        2.dp,
                                        if (isSelected) PrimaryPurple else TextMuted,
                                        androidx.compose.foundation.shape.CircleShape
                                    )
                                    .background(if (isSelected) PrimaryPurple else Color.Transparent),
                                contentAlignment = Alignment.Center
                            ) {
                                if (isSelected) {
                                    Box(
                                        modifier = Modifier
                                            .size(8.dp)
                                            .clip(androidx.compose.foundation.shape.CircleShape)
                                            .background(Color.White)
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.width(12.dp))

                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = style.displayName,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (isSelected) TextPrimary else TextSecondary
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    text = style.description,
                                    fontSize = 12.sp,
                                    color = TextMuted,
                                    lineHeight = 16.sp
                                )
                            }
                        }
                    }
                }
            }

            // Error Message
            AnimatedVisibility(visible = errorMessage != null) {
                errorMessage?.let { msg ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = Color(0xFF2D161A)),
                        border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF7F1D1D))
                    ) {
                        Text(
                            text = msg,
                            color = AccentOrange,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(12.dp)
                        )
                    }
                }
            }

            // Generate Button
            Button(
                onClick = {
                    viewModel.generateScripts { script ->
                        onNavigateToResults()
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                enabled = !isLoading && inputText.isNotBlank(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = PrimaryPurple,
                    disabledContainerColor = SurfaceVariantDark
                )
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        color = TextPrimary,
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = "Crafting Studio Script...",
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        color = TextPrimary
                    )
                } else {
                    Icon(
                        imageVector = Icons.Default.AutoAwesome,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = TextPrimary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Generate Script",
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp,
                        color = TextPrimary
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}
