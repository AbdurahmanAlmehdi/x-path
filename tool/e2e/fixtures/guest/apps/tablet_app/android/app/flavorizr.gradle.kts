val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.oneavant.guestTablet.dev"
            resValue(type = "string", name = "app_name", value = "Dev")
        }
        create("oneavant") {
            dimension = "flavor-type"
            applicationId = "com.oneavant.guestTablet"
            resValue(type = "string", name = "app_name", value = "Oneavant")
        }
    }
}
