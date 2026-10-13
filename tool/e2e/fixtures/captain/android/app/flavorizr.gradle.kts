import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.mataa.captain.dev"
            resValue(type = "string", name = "app_name", value = "Mataa Captain Dev")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.mataa.captain"
            resValue(type = "string", name = "app_name", value = "Mataa Captain")
        }
    }
}
