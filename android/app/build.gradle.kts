import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releasePropertiesFile = rootProject.file("key.properties")
val releaseProperties = Properties().apply {
    if (releasePropertiesFile.exists()) releasePropertiesFile.inputStream().use { load(it) }
}
val localAndroidProperties = Properties().apply {
    val propertiesFile = rootProject.file("local.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}
val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        if (!releasePropertiesFile.exists() || required.any { releaseProperties.getProperty(it).isNullOrBlank() }) {
            throw GradleException("Configure your private android/key.properties before building a release. Debug signing is never used for release.")
        }
        if (!file(releaseProperties.getProperty("storeFile")).isFile) {
            throw GradleException("The configured release keystore is unavailable.")
        }
    }
}
tasks.configureEach {
    if (name == "packageRelease" || name == "bundleRelease" || name == "validateSigningRelease") dependsOn(verifyReleaseSigning)
}

android {
    namespace = "com.example.geosustain_clean_arranged"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.geosustain_clean_arranged"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releasePropertiesFile.exists()) {
            create("release") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        debug {
            // Use an uppercase environment marker: Dart normalizes Windows
            // environment keys before Flutter starts Gradle.
            if (providers.environmentVariable("GEOSUSTAIN_PHASE01_QA").orNull == "true") {
                applicationIdSuffix = ".phase01qa"
                versionNameSuffix = "-phase01"
            }
        }
        release {
            signingConfig = if (releasePropertiesFile.exists()) signingConfigs.getByName("release") else null
        }
    }

    // Flutter adds an empty CMake project solely to provision the NDK. On
    // Windows its generated metadata can remain locked during configureCMake.
    // With that exact NDK already installed, the empty project is unnecessary.
    // Keep real app CMake projects and first-time NDK provisioning untouched.
    val sdkDirectory = localAndroidProperties.getProperty("sdk.dir")
    val installedNdk = sdkDirectory?.let {
        File(it, "ndk/$ndkVersion/source.properties").isFile
    } == true
    val cmakeProject = externalNativeBuild.cmake.path
    if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true) &&
        installedNdk &&
        cmakeProject?.invariantSeparatorsPath?.endsWith(
            "/flutter_tools/gradle/src/main/scripts/CMakeLists.txt"
        ) == true
    ) {
        externalNativeBuild.cmake.path = null
    }
}

flutter {
    source = "../.."
}
