pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "hearth-android"

// The iOS split, mirrored: `core` is the portable logic (transport, view
// model, face director, cards, config) and carries no Compose. `app` is the
// Android surface plus the device-owner receivers the appliance provisions.
include(":core")
include(":app")
