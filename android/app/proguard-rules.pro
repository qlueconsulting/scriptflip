# ScriptFlip ProGuard & R8 Rules
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable

# Kotlinx Serialization
-keepclassmembers class * {
    *** Companion;
}
-keepclasseswithmembers class * {
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers class * {
    @kotlinx.serialization.SerialName <fields>;
}
-keepclassmembers class com.qlueconsulting.scriptflip.data.model.** {
    <fields>;
}

# RevenueCat Purchases SDK
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# OkHttp & Okio
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Coroutines
-dontwarn kotlinx.coroutines.**

