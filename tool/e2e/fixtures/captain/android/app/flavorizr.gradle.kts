import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.orbit.captain.dev"
            resValue(type = "string", name = "app_name", value = "Orbit Captain Dev")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.orbit.captain"
            resValue(type = "string", name = "app_name", value = "Orbit Captain")
        }
    }
}
