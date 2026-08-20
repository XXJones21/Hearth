package com.hearth.app.ui.surfaces

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.AppsSurface
import com.hearth.core.surfaces.HouseApp

/**
 * What the house can reach, and what it can draw. Ported from the iOS
 * `AppsView`.
 *
 * Apps are grouped by STATE, in the house's own order and language: what is
 * in the house, what is known but waiting on a credential, and what was found
 * on this machine but not let in. The distinction matters because "not
 * working" and "not permitted" are different problems with different fixes,
 * and a flat list conflates them.
 */
@Composable
fun AppsScreen(config: ServerConfig, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<AppsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = AppsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Apps & Extensions", onBack) { padding ->
        val current = surface
        when {
            loading -> SurfaceLoading(padding)
            current == null -> SurfaceUnavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                if (!current.toolsEnabled) {
                    item {
                        SurfaceRowItem(
                            title = "Tools are switched off",
                            detail = "The house is answering from what it knows, " +
                                "and reaching nothing.",
                        )
                    }
                }

                for (state in GROUP_ORDER) {
                    appGroup(state, current.apps.filter { it.state == state })
                }

                item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }
                item { SurfaceSectionLabel("Cards this house can draw") }
                items(current.cards, key = { it.type }) { card ->
                    SurfaceRowItem(
                        title = card.type,
                        detail = card.purpose,
                        trailing = card.state.ifBlank { null },
                    )
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

private fun LazyListScope.appGroup(state: String, apps: List<HouseApp>) {
    if (apps.isEmpty()) return
    item(key = "group-$state") {
        Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            Text(
                groupTitle(state),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                groupCaption(state),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    items(apps, key = { it.key }) { app ->
        SurfaceRowItem(
            title = app.name,
            detail = buildString {
                append(app.tagline)
                // What it is waiting on is the only actionable thing on this
                // page, so it goes where it will be read.
                if (app.state == "setup" && app.needs.isNotEmpty()) {
                    append("  Needs ")
                    append(app.needs.joinToString(" and "))
                }
                if (app.who.isNotEmpty()) {
                    append("  Offered to ")
                    append(app.who.joinToString(", "))
                }
            },
            trailing = if (app.more > 0) "${app.more} tools" else app.kind.ifBlank { null },
        )
    }
}
