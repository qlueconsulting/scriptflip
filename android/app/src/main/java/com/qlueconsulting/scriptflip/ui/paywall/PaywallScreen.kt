package com.qlueconsulting.scriptflip.ui.paywall

import android.app.Activity
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.qlueconsulting.scriptflip.data.billing.SubscriptionManager
import com.qlueconsulting.scriptflip.data.model.SubscriptionTier
import com.qlueconsulting.scriptflip.ui.theme.AccentCyan
import com.qlueconsulting.scriptflip.ui.theme.AccentGreen
import com.qlueconsulting.scriptflip.ui.theme.BgDark
import com.qlueconsulting.scriptflip.ui.theme.CardBorder
import com.qlueconsulting.scriptflip.ui.theme.PrimaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SecondaryPurple
import com.qlueconsulting.scriptflip.ui.theme.SurfaceDark
import com.qlueconsulting.scriptflip.ui.theme.SurfaceVariantDark
import com.qlueconsulting.scriptflip.ui.theme.TextMuted
import com.qlueconsulting.scriptflip.ui.theme.TextPrimary
import com.qlueconsulting.scriptflip.ui.theme.TextSecondary
import kotlinx.coroutines.launch

@Composable
fun PaywallScreen(
    subscriptionManager: SubscriptionManager,
    onClose: () -> Unit
) {
    val activeTier by subscriptionManager.activeTier.collectAsState()
    val weeklyPkg by subscriptionManager.weeklyPackage.collectAsState()
    val monthlyPkg by subscriptionManager.monthlyPackage.collectAsState()
    val isPurchasing by subscriptionManager.isPurchasing.collectAsState()
    val errorMessage by subscriptionManager.errorMessage.collectAsState()

    var selectedTier by remember { mutableStateOf(SubscriptionTier.PRO_MONTHLY) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val activity = context as? Activity

    Scaffold(
        containerColor = BgDark,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.End
            ) {
                IconButton(onClick = onClose) {
                    Icon(imageVector = Icons.Default.Close, contentDescription = "Close", tint = TextPrimary)
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Unlock ScriptFlip Pro",
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                textAlign = TextAlign.Center
            )

            Text(
                text = "Generate studio-ready scripts at scale with higher quotas and priority AI turnaround.",
                fontSize = 14.sp,
                color = TextSecondary,
                textAlign = TextAlign.Center
            )

            // Features Checklist
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
                    FeatureRow(title = "Up to 250 scripts / month")
                    FeatureRow(title = "Full Studio Teleprompter & Mirroring")
                    FeatureRow(title = "Viral Hook & Retention Frameworks")
                    FeatureRow(title = "Export to Shorts, Reels & TikTok")
                }
            }

            // Tier Cards
            TierCard(
                title = "Pro Monthly",
                badge = "BEST VALUE",
                quota = "250 scripts / month",
                price = monthlyPkg?.product?.price?.formatted ?: "$19.99 / month",
                isSelected = selectedTier == SubscriptionTier.PRO_MONTHLY,
                onClick = { selectedTier = SubscriptionTier.PRO_MONTHLY }
            )

            TierCard(
                title = "Pro Weekly",
                badge = null,
                quota = "50 scripts / week",
                price = weeklyPkg?.product?.price?.formatted ?: "$4.99 / week",
                isSelected = selectedTier == SubscriptionTier.PRO_WEEKLY,
                onClick = { selectedTier = SubscriptionTier.PRO_WEEKLY }
            )

            if (errorMessage != null) {
                Text(
                    text = errorMessage ?: "",
                    fontSize = 12.sp,
                    color = AccentGreen,
                    textAlign = TextAlign.Center
                )
            }

            // Purchase Button
            Button(
                onClick = {
                    if (activity != null) {
                        val pkg = if (selectedTier == SubscriptionTier.PRO_MONTHLY) monthlyPkg else weeklyPkg
                        if (pkg != null) {
                            scope.launch {
                                val success = subscriptionManager.purchasePackage(activity, pkg)
                                if (success) onClose()
                            }
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                enabled = !isPurchasing,
                colors = ButtonDefaults.buttonColors(containerColor = PrimaryPurple)
            ) {
                if (isPurchasing) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), color = TextPrimary)
                } else {
                    Text(
                        text = "Continue with ${if (selectedTier == SubscriptionTier.PRO_MONTHLY) "Monthly" else "Weekly"}",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Restore Purchases
            TextButton(
                onClick = {
                    scope.launch {
                        val restored = subscriptionManager.restorePurchases()
                        if (restored) onClose()
                    }
                }
            ) {
                Text(text = "Restore Purchases", color = TextSecondary, fontSize = 13.sp)
            }

            Spacer(modifier = Modifier.height(20.dp))
        }
    }
}

@Composable
private fun FeatureRow(title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = AccentGreen,
            modifier = Modifier.size(18.dp)
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(text = title, fontSize = 13.sp, color = TextPrimary)
    }
}

@Composable
private fun TierCard(
    title: String,
    badge: String?,
    quota: String,
    price: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(if (isSelected) SurfaceVariantDark else SurfaceDark)
            .border(
                2.dp,
                if (isSelected) SecondaryPurple else CardBorder,
                RoundedCornerShape(16.dp)
            )
            .clickable(onClick = onClick)
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = title,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    if (badge != null) {
                        Spacer(modifier = Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(SecondaryPurple)
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = badge,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = TextPrimary
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(text = quota, fontSize = 12.sp, color = TextSecondary)
            }

            Text(
                text = price,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = AccentCyan
            )
        }
    }
}
