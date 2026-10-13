val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.harbor.guestTablet.dev"
            resValue(type = "string", name = "app_name", value = "Dev")
        }
        create("harbor") {
            dimension = "flavor-type"
            applicationId = "com.harbor.guestTablet"
            resValue(type = "string", name = "app_name", value = "Harbor")
        }
    }
}
