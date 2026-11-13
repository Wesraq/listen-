allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Keep plugin modules on compileSdk 36 so AAR metadata checks pass with newer lifecycle plugins.
// evaluationDependsOn(":app") can evaluate subprojects early, so handle both cases.
subprojects {
    fun bumpCompileSdk() {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.compileSdkVersion(36)
    }
    if (state.executed) {
        bumpCompileSdk()
    } else {
        afterEvaluate { bumpCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
