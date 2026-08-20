package com.hearth.app.ui.surfaces

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.theme.HearthColors
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.AppsSurface
import com.hearth.core.surfaces.HouseApp

/**
 * What the house can reach, and who may ask. Ported from the iOS `AppsView`.
 *
 * Apps are grouped by STATE in the house's own order and language, because
 * "not working" and "not permitted" are different problems with different
 * fixes and a flat list conflates them. On device is its own group: those
 * entries belong to the phone rather than the house, and the footnote says
 * which of the two a person can actually change from here.
 */
@Composable
fun AppsScreen(
    config: ServerConfig,
    speechAvailable: Boolean,
    onCards: () -> Unit,
    onBack: () -> Unit,
) {
    var surface by remember { mutableStateOf<AppsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = AppsSurface.load(config)
        loading = false
    }

    SurfaceBackground {
        LazyColumn {
            item { SurfaceTopBar(onBack = onBack, trailingLabel = "Cards", onTrailing = onCards) }
            item {
                SurfaceTitle(
                    title = "Apps",
                    subtitle = "what the house can reach, and who may ask",
                    note = "Changes are made at the desk, on the machine running " +
                        "the house. This phone reads.",
                )
            }

            val current = surface
            when {
                loading -> item { SurfaceLoadingBlock() }
                current == null -> item { SurfaceUnavailableBlock() }
                else -> {
                    for (state in GROUP_ORDER) {
                        appGroup(state, current.apps.filter { it.state == state })
                    }

                    item { SectionHeading("On device", "this phone's own, not the house's") }
                    item {
                        GroupCard {
                            GroupRow(
                                title = "Speech",
                                detail = "Android's on-device recogniser, asked for " +
                                    "offline first so the audio never leaves the phone.",
                                badge = "Sp" to HearthColors.linen,
                                chips = listOf("This phone" to HearthColors.fawn),
                                status = if (speechAvailable) "On device, en-US"
                                else "No recogniser on this device",
                            )
                            RowDivider()
                            GroupRow(
                                title = "Widgets",
                                detail = "The persona and Tap to talk on the cover " +
                                    "screen and the home screen.",
                                badge = "Wi" to HearthColors.linen,
                                chips = listOf("This phone" to HearthColors.fawn),
                                status = "Not added yet",
                            )
                        }
                    }

                    item {
                        SurfaceFootnote(
                            "House apps are read-only here. Toggling one and granting " +
                                "it to a persona happens at the desk.",
                            "On-device entries are this phone's to change.",
                        )
                    }
                }
            }
        }
    }
}

/** The house's own order: in, waiting, and merely present. */
private val GROUP_ORDER = listOf("active", "setup", "available")

private fun groupTitle(state: String) = when (state) {
    "active" -> "In the house"
    "setup" -> "Needs setup"
    else -> "Available"
}

private fun groupCaption(state: String) = when (state) {
    "active" -> "offered to at least one persona"
    "setup" -> "known, waiting on a credential"
    else -> "found on this machine, not let in yet"
}

/** The risk chips the house hands out, coloured by how much they can do. */
private fun chipsFor(app: HouseApp): List<Pair<String, Color>> {
    val out = mutableListOf<Pair<String, Color>>()
    // KIND and RISK only. transport is a sentence explaining where the thing
    // runs ("on disk, this machine only"), and using it as a chip produced
    // three-line pills that swamped the row.
    when (app.kind) {
        "core" -> out.add("Always on" to HearthColors.honey)
        "cli" -> out.add("CLI" to HearthColors.fawn)
    }
    when (app.risk) {
        "control" -> out.add("Control" to HearthColors.ember)
        "write" -> out.add("Write" to HearthColors.fennec)
    }
    return out.filter { it.first.isNotBlank() }
}

private fun LazyListScope.appGroup(state: String, apps: List<HouseApp>) {
    if (apps.isEmpty()) return
    item(key = "head-$state") { SectionHeading(groupTitle(state), groupCaption(state)) }
    item(key = "group-$state") {
        GroupCard {
            apps.forEachIndexed { index, app ->
                GroupRow(
                    title = app.name,
                    detail = buildString {
                        append(app.tagline)
                        // What it waits on is the only actionable thing here.
                        if (app.state == "setup" && app.needs.isNotEmpty()) {
                            append("\nNeeds ")
                            append(app.needs.joinToString(" and "))
                        }
                    },
                    badge = app.name.take(2) to badgeTint(app),
                    chips = chipsFor(app),
                    showChevron = true,
                )
                if (index < apps.lastIndex) RowDivider()
            }
        }
    }
    item(key = "gap-$state") {
        androidx.compose.foundation.layout.Spacer(Modifier.padding(bottom = 4.dp))
    }
}

private fun badgeTint(app: HouseApp): Color = when {
    app.kind == "core" -> HearthColors.fennec
    app.state == "active" -> HearthColors.honey
    else -> HearthColors.linen
}
