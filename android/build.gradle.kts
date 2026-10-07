allprojects {
    repositories {
        // AndroidX / Google artifacts resolve from Google Maven only.
        // Content filtering stops Gradle from querying Maven Central's
        // metadata for these groups, which was failing with HTTP 429
        // (Too Many Requests) when resolving androidx.test:runner:1.2+
        // used by the integration_test plugin.
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("androidx\\..*")
                includeGroupByRegex("com\\.google.*")
            }
        }
        maven { url = uri("https://maven.aliyun.com/repository/central") } // Central mirror (repo.maven.apache.org rate-limits this network with 429s)
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

subprojects {
    // The integration_test plugin declares a dynamic dependency
    // (androidx.test:runner:1.2+) that forces Gradle to download Maven
    // metadata on every build — which fails behind rate limits (HTTP 429).
    // Pin concrete versions so resolution is fully offline-cacheable.
    configurations.all {
        resolutionStrategy.force("androidx.test:runner:1.6.2")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}