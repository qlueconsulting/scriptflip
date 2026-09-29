package com.qlueconsulting.scriptflip.ui.about

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.R
import com.qlueconsulting.scriptflip.data.model.SubscriptionTier
import com.qlueconsulting.scriptflip.ui.generator.ScriptGeneratorViewModel
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import com.qlueconsulting.scriptflip.ui.theme.BgDark
import com.qlueconsulting.scriptflip.ui.theme.CardBorder
import com.qlueconsulting.scriptflip.ui.theme.SecondaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SurfaceDark
import com.qlueconsulting.scriptflip.ui.theme.SurfaceVariantDark
import com.qlueconsulting.scriptflip.ui.theme.TextMuted
import com.qlueconsulting.scriptflip.ui.theme.TextPrimary
import com.qlueconsulting.scriptflip.ui.theme.TextSecondary

@Composable
fun AboutScreen(
    viewModel: ScriptGeneratorViewModel,
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val activeTier by viewModel.subscriptionManager.activeTier.collectAsState()

    Scaffold(
        containerColor = BgDark,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onNavigateBack) {
                    Icon(imageVector = Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "About ScriptFlip",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary
                )
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // App Icon & Header
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp, bottom = 8.dp)
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.padding(bottom = 12.dp)
                ) {
                    // Ambient cyan glow
                    Box(
                        modifier = Modifier
                            .size(140.dp, 80.dp)
                            .background(
                                brush = Brush.radialGradient(
                                    colors = listOf(
                                        Color(0x5500E5FF),
                                        Color(0x1800E5FF),
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
                            .widthIn(max = 220.dp)
                            .height(100.dp)
                    )
                }

                Text(
                    text = "Version 1.0.0 (Build 1)",
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    color = TextMuted
                )
            }

            // App Branding Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceDark),
                border = androidx.compose.foundation.BorderStroke(1.dp, CardBorder)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "ScriptFlip for Android",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(text = "Version 1.0.0 (Build 1)", fontSize = 12.sp, color = TextMuted)
                    Spacer(modifier = Modifier.height(10.dp))
                    Text(
                        text = "AI-powered video script extraction, script generation, and studio teleprompter engineered for content creators.",
                        fontSize = 13.sp,
                        color = TextSecondary,
                        lineHeight = 19.sp
                    )
                }
            }

            // Legal & Support Links
            Text(
                text = "Legal & Support",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceDark),
                border = androidx.compose.foundation.BorderStroke(1.dp, CardBorder)
            ) {
                Column {
                    LinkRow(title = "Privacy Policy", url = "https://gist.github.com/qlueconsulting/dd318693733c41c5a20ae5e39d585985", context = context)
                    HorizontalDivider(color = Color.White.copy(alpha = 0.08f), thickness = 1.dp)
                    LinkRow(title = "Terms of Use", url = "https://gist.github.com/qlueconsulting/1b038663d0ea21b8ccda1623b7e67f97", context = context)
                    HorizontalDivider(color = Color.White.copy(alpha = 0.08f), thickness = 1.dp)
                    LinkRow(title = "Customer Support", url = "https://gist.github.com/qlueconsulting/1b038663d0ea21b8ccda1623b7e67f97", context = context)
                }
            }

            // Diagnostic & Tester Controls
            Text(
                text = "Testing Diagnostics",
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceDark),
                border = androidx.compose.foundation.BorderStroke(1.dp, CardBorder)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = "Active Tier: ${activeTier.displayName}",
                        fontSize = 13.sp,
                        color = AccentCyan,
                        fontWeight = FontWeight.Bold
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = {
                                viewModel.subscriptionManager.setTesterOverride(SubscriptionTier.FREE)
                                viewModel.refreshUsage()
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = SurfaceVariantDark)
                        ) {
                            Text(text = "Free", fontSize = 11.sp, color = TextPrimary)
                        }

                        Button(
                            onClick = {
                                viewModel.subscriptionManager.setTesterOverride(SubscriptionTier.PRO_WEEKLY)
                                viewModel.refreshUsage()
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = SurfaceVariantDark)
                        ) {
                            Text(text = "Pro Wk", fontSize = 11.sp, color = TextPrimary)
                        }

                        Button(
                            onClick = {
                                viewModel.subscriptionManager.setTesterOverride(SubscriptionTier.PRO_MONTHLY)
                                viewModel.refreshUsage()
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = SurfaceVariantDark)
                        ) {
                            Text(text = "Pro Mo", fontSize = 11.sp, color = TextPrimary)
                        }
                    }

                    Button(
                        onClick = {
                            viewModel.usageTracker.resetUsage()
                            viewModel.refreshUsage()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = SurfaceVariantDark)
                    ) {
                        Text(text = "Reset Quotas to Zero", fontSize = 12.sp, color = TextSecondary)
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun LinkRow(title: String, url: String, context: android.content.Context) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                context.startActivity(intent)
            }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = title, fontSize = 14.sp, color = TextPrimary)
        Icon(
            imageVector = Icons.AutoMirrored.Filled.OpenInNew,
            contentDescription = null,
            tint = TextMuted,
            modifier = Modifier.size(16.dp)
        )
    }
}
