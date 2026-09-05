import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Local properties
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode")?.toIntOrNull() ?: 1
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

// Keystore properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.strusa"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            java.srcDir("src/main/kotlin")
        }
    }

    defaultConfig {
        applicationId = "com.example.strusa"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        ndkVersion = "28.2.13676358"
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            applicationIdSuffix = null
        }
    }

    buildFeatures {
        buildConfig = true
    }

    tasks.whenTaskAdded {
        if (name == "assembleRelease") {
            doLast {
                val src = layout.buildDirectory.file("outputs/apk/release/app-release.apk").get().asFile
                val dst = file("${rootProject.projectDir}/../build/app/outputs/flutter-apk/app-release.apk")
                if (src.exists()) {
                    dst.parentFile.mkdirs()
                    src.copyTo(dst, overwrite = true)
                    println("✅ APK copied to: ${dst.absolutePath}")
                } else {
                    println("❌ Source APK not found at: ${src.absolutePath}")
                }
            }
        }
        if (name == "assembleDebug") {
            doLast {
                val src = layout.buildDirectory.file("outputs/apk/debug/app-debug.apk").get().asFile
                val dst = file("${rootProject.projectDir}/../build/app/outputs/flutter-apk/app-debug.apk")
                if (src.exists()) {
                    dst.parentFile.mkdirs()
                    src.copyTo(dst, overwrite = true)
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.multidex:multidex:2.0.1")
}