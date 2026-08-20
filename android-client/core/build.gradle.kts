plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hearth.core"
    compileSdk = 35

    defaultConfig {
        // The Razr 40 Ultra ships Android 13; nothing older matters.
        minSdk = 33
        testOptions.targetSdk = 35
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // The iOS Core package declares zero external dependencies. This module
    // holds the line as far as Android allows: OkHttp for the socket, and
    // nothing else. No Compose here -- if a file in this module needs a
    // Composable, it belongs in :app instead.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // The token vault: the Keystore-backed counterpart of the iOS Keychain.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
