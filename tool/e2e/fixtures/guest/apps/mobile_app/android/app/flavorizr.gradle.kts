val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.harbor.guestExperience.dev"
            resValue(type = "string", name = "app_name", value = "Dev")
        }
        create("seaview") {
            dimension = "flavor-type"
            applicationId = "com.harbor.guestExperience.seaview"
            resValue(type = "string", name = "app_name", value = "Seaview")
        }
        create("harbor") {
            dimension = "flavor-type"
            applicationId = "com.harbor.guestExperience"
            resValue(type = "string", name = "app_name", value = "Harbor")
        }
    }
}
