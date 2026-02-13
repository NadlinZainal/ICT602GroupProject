plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ict602_project"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ✅ DESUGARING - GUNA isCoreLibraryDesugaringEnabled
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.ict602_project"
        // ✅ WAJIB: SET minSdk = 21 (JANGAN guna flutter.minSdkVersion)
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ✅ MULTIDEX - GUNA multiDexEnabled (bukan isMultiDexEnabled)
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ DESUGARING LIBRARY
    add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.4")

    // ✅ MULTIDEX SUPPORT
    add("implementation", "androidx.multidex:multidex:2.0.1")

    // ✅ FIREBASE BoM
    add("implementation", platform("com.google.firebase:firebase-bom:33.5.1"))
}
