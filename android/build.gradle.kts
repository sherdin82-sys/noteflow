allprojects {
    repositories {
        google()
        mavenCentral()
    }
    project.extensions.extraProperties.set(
        "flutter",
        mapOf(
            "compileSdkVersion" to 34,
            "minSdkVersion" to 24,
            "targetSdkVersion" to 34
        )
    )
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            if (androidExt.compileSdkVersion == null) {
                androidExt.compileSdkVersion(34)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
