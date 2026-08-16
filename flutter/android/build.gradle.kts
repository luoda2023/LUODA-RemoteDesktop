rootProject.buildDir = file("../build")
subprojects {
    project.buildDir = file("${rootProject.buildDir}/${project.name}")
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { setUrl("https://jitpack.io") }
    }
}

subprojects {
    // Java 17 is the default for Android Gradle Plugin 8.x
    // The whenPluginAdded block was removed because it conflicts with
    // newer Gradle Kotlin DSL versions.

    // AGP 8.x requires an explicit namespace on every Android module.
    // Older third-party plugins (e.g. external_path) omit it, so we inject
    // it from their AndroidManifest.xml package attribute when missing.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            if (namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val m = Regex("""package\s*=\s*"([^"]+)"""").find(manifestFile.readText())
                    if (m != null) {
                        namespace = m.groupValues[1]
                        println("Injected namespace ${m.groupValues[1]} for ${project.name}")
                    }
                }
            }
        }
    }
}
