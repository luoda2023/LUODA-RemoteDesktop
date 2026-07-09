import com.google.protobuf.gradle.*
import groovy.json.JsonSlurper
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.google.protobuf") version "0.9.4"
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { reader -> localProperties.load(reader) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "2.0"

fun findRustlsPlatformVerifierMavenDir(): String? {
    try {
        val dependencyText = providers.exec {
            workingDir = File("../..")
            commandLine("cargo", "metadata", "--format-version", "1")
        }.standardOutput.asText.get()

        val dependencyJson = JsonSlurper().parseText(dependencyText) as Map<*, *>
        val packages = dependencyJson["packages"] as List<*>
        val pkg = packages.find { (it as Map<*, *>)["name"] == "rustls-platform-verifier-android" }

        @Suppress("UNCHECKED_CAST")
        val pkgMap = pkg as Map<String, Any>?
        if (pkgMap == null) return null

        val manifestPath = File(pkgMap["manifest_path"] as String)
        val mavenDir = File(manifestPath.parentFile, "maven")

        if (!mavenDir.exists()) return null

        println("Found rustls-platform-verifier maven repo at: ${mavenDir.path}")
        return mavenDir.path
    } catch (e: Exception) {
        println("Warning: Could not locate rustls-platform-verifier maven repo: ${e.message}")
        return null
    }
}

val rustlsMavenDir = findRustlsPlatformVerifierMavenDir()

repositories {
    if (rustlsMavenDir != null) {
        maven {
            url = uri(rustlsMavenDir)
            metadataSources {
                mavenPom()
                artifact()
            }
        }
    }
}

tasks.register<Copy>("copyProtoFiles") {
    from(file("../../../libs/hbb_common/protos"))
    into(file("src/main/proto"))
    include("*.proto")
}

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:3.20.1"
    }
    generateProtoTasks {
        all().forEach { task ->
            task.dependsOn("copyProtoFiles")
            task.builtins {
                create("java") {
                    option("lite")
                }
            }
        }
    }
}

android {
    namespace = "com.luoda.remote"
    compileSdkVersion(34)

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.luoda.remote"
        minSdkVersion(22)
        targetSdkVersion(33)
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as? String
            val storeFileObj = storeFilePath?.let { rootProject.file(it) }
            if (storeFileObj?.exists() == true) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = storeFileObj
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // 与官方 rustdesk 一致：release 始终用 signingConfigs.release（而非 debug 签名）
            // 如果 key.properties 不存在或 storeFile 不存在，则为 null 签名（装不上）。
            // 见官方：https://github.com/rustdesk/rustdesk/blob/master/flutter/android/app/build.gradle
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.protobuf:protobuf-javalite:3.20.1")
    implementation("androidx.media:media:1.6.0")
    implementation("com.github.getActivity:XXPermissions:18.5")
    implementation("org.jetbrains.kotlin:kotlin-stdlib") {
        version { strictly("1.9.24") }
    }
    implementation("com.caverock:androidsvg-aar:1.4")
    implementation("rustls:rustls-platform-verifier:0.1.1")
}
