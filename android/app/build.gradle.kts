plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlinx.serialization)
}

android {
    namespace = "com.qlueconsulting.scriptflip"
    compileSdk = 36

    val resolvedVersionCode = providers.environmentVariable("VERSION_CODE").orNull?.toIntOrNull()
        ?: providers.gradleProperty("versionCode").orNull?.toIntOrNull()
        ?: 1
    val resolvedVersionName = providers.environmentVariable("VERSION_NAME").orNull
        ?: providers.gradleProperty("versionName").orNull
        ?: "1.0.0"

    defaultConfig {
        applicationId = "com.qlueconsulting.scriptflip"
        minSdk = 26
        targetSdk = 36
        versionCode = resolvedVersionCode
        versionName = resolvedVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField("String", "SUPABASE_URL", "\"https://tcgonpbwenimvilzquoz.supabase.co\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjZ29ucGJ3ZW5pbXZpbHpxdW96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyOTc0MDQsImV4cCI6MjEwMTg3MzQwNH0.BMVRR6wcnLa_mSsyzgS66xDHCqlu1j2PG3k2mKoVG_U\"")
        buildConfigField("String", "REVENUECAT_API_KEY", "\"goog_pcnOuyAgmkrXhYeYebsKaeqhlaF\"")
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("KEYSTORE_PATH")
            if (!keystorePath.isNullOrBlank()) {
                val ksFile = listOf(
                    file(keystorePath),
                    rootProject.file(keystorePath),
                    File(keystorePath)
                ).firstOrNull { it.exists() }

                if (ksFile != null) {
                    storeFile = ksFile
                    storePassword = System.getenv("KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("KEY_ALIAS")
                    keyPassword = System.getenv("KEY_PASSWORD")
                } else if (System.getenv("CI") == "true") {
                    throw GradleException("Keystore file '$keystorePath' specified in KEYSTORE_PATH was not found in project or root directories!")
                }
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("release")?.takeIf { it.storeFile != null }
                ?: signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)

    implementation(libs.revenuecat.purchases)

    debugImplementation(libs.androidx.ui.tooling)
}
