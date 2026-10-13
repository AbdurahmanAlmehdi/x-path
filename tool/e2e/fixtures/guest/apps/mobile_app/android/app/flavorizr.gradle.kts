val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.oneavant.guestExperience.dev"
            resValue(type = "string", name = "app_name", value = "Dev")
        }
        create("iniala") {
            dimension = "flavor-type"
            applicationId = "com.oneavant.guestExperience.iniala"
            resValue(type = "string", name = "app_name", value = "Iniala")
        }
        create("oneavant") {
            dimension = "flavor-type"
            applicationId = "com.oneavant.guestExperience"
            resValue(type = "string", name = "app_name", value = "Oneavant")
        }
    }
}
