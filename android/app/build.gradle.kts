plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.example.finance_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.finance_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    splits {
        abi {
            isEnable = false
            reset()
            include("armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }
}

@Suppress("UnstableApiUsage")
fun apkFileName(verName: String, buildType: String) =
    "Uchet_finansov-${verName}-${buildType}.apk"

// Попытка определить версию AGP и выбрать API
val agpVer: String = try {
    com.android.build.gradle.internal.Version.ANDROID_GRADLE_PLUGIN_VERSION
} catch (_: Throwable) {
    "8.0.0" // пусть по умолчанию будет новая ветка
}

if (agpVer.startsWith("8") || agpVer.startsWith("9")) {
    // === AGP 8+ путь: androidComponents ===
    androidComponents {
        onVariants(selector().all()) { variant ->
            // versionName: пробуем из variant, иначе из defaultConfig
            val vName = variant.outputs.first().versionName.orNull
                ?: android.defaultConfig.versionName
                ?: "0.0.0"
            val bType = variant.buildType

            variant.outputs.forEach { out ->
                // Без import: полное имя класса
                val apkOut = out as? com.android.build.api.variant.ApkVariantOutput
                if (apkOut != null) {
                    apkOut.outputFileName.set(apkFileName(vName, bType))
                }
            }
        }
    }
} else {
    // === AGP 7.x путь: applicationVariants/all + internal API ===
    @Suppress("DEPRECATION")
    android.applicationVariants.all {
        val vName = this.versionName ?: android.defaultConfig.versionName ?: "0.0.0"
        val bType = this.buildType.name
        outputs.all {
            // Ветка для старых AGP: используем internal BaseVariantOutputImpl
            val base = this as? com.android.build.gradle.internal.api.BaseVariantOutputImpl
            base?.outputFileName = apkFileName(vName, bType)
        }
    }
}

flutter {
    source = "../.."
}
