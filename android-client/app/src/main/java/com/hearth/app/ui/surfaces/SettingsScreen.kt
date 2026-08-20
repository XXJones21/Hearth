package com.hearth.app.ui.surfaces

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.SettingsSurface
import com.hearth.core.surfaces.probeHealth
import kotlinx.coroutines.launch

/**
 * The house's own state, plus the one thing this client owns: the address it
 * dials and the pairing behind it. Ported from the iOS `HearthSettingsView`.
 *
 * Test and Apply are deliberately different verbs. Test probes whatever is
 * TYPED and then puts the saved value back, so a wrong address is discovered
 * without taking the live socket down. Apply commits and redials, and
 * pointing at a different house also surrenders the old house's key, because
 * presenting house A's token to house B earns a 1008 close and a reconnect
 * loop behind it.
 */
@Composable
fun SettingsScreen(
    config: ServerConfig,
    autoReconnect: Boolean,
    onAutoReconnect: (Boolean) -> Unit,
    onApply: () -> Unit,
    onForget: () -> Unit,
    onBack: () -> Unit,
) {
    var surface by remember { mutableStateOf<SettingsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    var address by remember { mutableStateOf(config.address) }
    var probeState by remember { mutableStateOf<String?>(null) }
    var probing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        surface = SettingsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Settings", onBack) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item { SurfaceSectionLabel("Connection") }

            item {
                Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                    OutlinedTextField(
                        value = address,
                        onValueChange = {
                            address = it
                            probeState = null
                        },
                        label = { Text("House address") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(
                        modifier = Modifier.padding(top = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        TextButton(
                            enabled = !probing,
                            onClick = {
                                probing = true
                                probeState = null
                                scope.launch {
                                    val previous = config.address
                                    // Stage the typed value, probe it, then
                                    // put the saved one back. A probe must
                                    // never cost the pairing.
                                    config.address = address
                                    val result = probeHealth(config)
                                    val probed = config.address
                                    config.address = previous
                                    probeState = if (result != null) {
                                        val brain =
                                            if (result.brainReady) "ready" else "not ready"
                                        "$probed answered in ${result.latencyMs} ms, " +
                                            "brain $brain (${result.brainBackend})"
                                    } else {
                                        "No answer from $probed."
                                    }
                                    probing = false
                                }
                            },
                        ) { Text(if (probing) "Testing..." else "Test") }

                        Button(
                            onClick = {
                                config.commitAddress(address)
                                onApply()
                            },
                        ) { Text("Apply and reconnect") }
                    }
                    probeState?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
            }

            item {
                SurfaceRowItem(
                    title = "Reconnect automatically",
                    detail = "Off stops the client dialing back after a drop. " +
                        "For debugging a house; leave it on for daily use.",
                    trailing = if (autoReconnect) "On" else "Off",
                    onClick = { onAutoReconnect(!autoReconnect) },
                )
            }

            item {
                SurfaceRowItem(
                    title = "Paired",
                    detail = if (config.isPaired) "This device has a key"
                    else "Not paired with any house",
                    trailing = if (config.isPaired) "Forget" else null,
                    onClick = if (config.isPaired) onForget else null,
                )
            }

            item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }

            val current = surface
            when {
                loading -> item { SurfaceLoading(PaddingValues(0.dp)) }

                current == null -> item {
                    SurfaceRowItem(
                        title = "The house",
                        detail = "Did not answer for its own settings.",
                    )
                }

                else -> {
                    item { SurfaceSectionLabel("The house") }
                    item {
                        SurfaceRowItem(
                            title = "Brain",
                            detail = current.brainBackend.ifBlank { "unknown" },
                            trailing = current.serverVersion.ifBlank { null },
                        )
                    }
                    current.engram?.let { engram ->
                        item {
                            SurfaceRowItem(
                                title = "Second brain",
                                detail = if (engram.connected) engram.path
                                else "Not connected",
                                trailing = if (engram.entries > 0) "${engram.entries}"
                                else null,
                            )
                        }
                    }
                    items(current.connections, key = { it.key }) { connection ->
                        SurfaceRowItem(
                            title = connection.name,
                            detail = connection.detail,
                            trailing = connection.state,
                        )
                    }
                }
            }
        }
    }
}
