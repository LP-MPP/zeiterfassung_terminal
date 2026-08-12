import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

fun signingValue(environmentName: String, propertyName: String): String =
    System.getenv(environmentName)
        ?: keystoreProperties.getProperty(propertyName)
        ?: throw GradleException(
            "Missing Android release signing value '$propertyName'. " +
                "Copy android/key.properties.example to android/key.properties."
        )

android {
    namespace = "de.mpp.zeiterfassung.terminal"
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
        applicationId = "de.mpp.zeiterfassung.terminal"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file(signingValue("ZEITERFASSUNG_KEYSTORE", "storeFile"))
            storePassword = signingValue("ZEITERFASSUNG_STORE_PASSWORD", "storePassword")
            keyAlias = signingValue("ZEITERFASSUNG_KEY_ALIAS", "keyAlias")
            keyPassword = signingValue("ZEITERFASSUNG_KEY_PASSWORD", "keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
