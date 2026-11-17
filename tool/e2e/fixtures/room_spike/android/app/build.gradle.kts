plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.harbor.spike.room_scene_spike"

    defaultConfig {
        // TODO: Specify your own unique Application ID.
        applicationId = "com.harbor.spike.room_scene_spike"
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
