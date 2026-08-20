package com.hearth.app.ui.surfaces

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
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
import com.hearth.core.surfaces.PersonaEntry
import com.hearth.core.surfaces.PersonaSurface
import com.hearth.core.surfaces.applyPersonaEdits
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Who lives in the house, ported from the iOS `PersonaView`.
 *
 * The sections are in the desktop's order because the order is the argument:
 * who they are, then how they are (the prompt, which IS the persona), then
 * voice, presence, what they may do, and how they think.
 *
 * Exactly ONE thing is editable here, and it is the prompt. Edits are batched
 * behind Save and nothing writes on a keystroke: a persona is hours of
 * writing, and an autosave turns a stray tap into a permanent edit. Internal
 * personas are the house's own machinery and are not listed.
 */
@Composable
fun PersonaScreen(config: ServerConfig, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<PersonaSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    var open by remember { mutableStateOf<PersonaEntry?>(null) }

    LaunchedEffect(Unit) {
        surface = PersonaSurface.load(config)
        loading = false
    }

    val current = open
    if (current != null) {
        PersonaDetail(config, current) { changed ->
            open = null
            if (changed) {
                loading = true
                surface = null
            }
        }
        LaunchedEffect(loading, surface) {
            if (loading && surface == null) {
                surface = PersonaSurface.load(config)
                loading = false
            }
        }
        return
    }

    SurfaceScaffold("Persona", onBack) { padding ->
        val people = surface?.personas
        when {
            loading -> SurfaceLoading(padding)
            people.isNullOrEmpty() -> SurfaceUnavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                items(people.filterNot { it.internal }, key = { it.key }) { person ->
                    SurfaceRowItem(
                        title = person.name,
                        detail = person.description,
                        trailing = person.form.ifBlank { null },
                        onClick = { open = person },
                    )
                }
            }
        }
    }
}

@Composable
private fun PersonaDetail(
    config: ServerConfig,
    person: PersonaEntry,
    onClose: (Boolean) -> Unit,
) {
    var draftPrompt by remember(person.key) { mutableStateOf(person.systemPrompt) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val hasEdits = draftPrompt != person.systemPrompt

    SurfaceScaffold(person.name, { onClose(false) }) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item { SurfaceSectionLabel("Who they are") }
            item {
                SurfaceRowItem(
                    title = person.name,
                    detail = person.description,
                    trailing = person.classification.ifBlank { null },
                )
            }

            item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }
            item { SurfaceSectionLabel("How they are") }
            item {
                Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                    Text(
                        "This is the persona. Everything else on this page is " +
                            "how they are carried.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = draftPrompt,
                        onValueChange = {
                            draftPrompt = it
                            error = null
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 220.dp)
                            .padding(top = 8.dp),
                    )
                }
            }

            item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }
            item { SurfaceSectionLabel("Voice") }
            item {
                SurfaceRowItem(
                    title = person.voice.ifBlank { "No clone" },
                    detail = "The clone the house speaks this persona with.",
                )
            }

            item { SurfaceSectionLabel("Presence") }
            item {
                SurfaceRowItem(
                    title = person.form.ifBlank { "orb" },
                    detail = "How they are drawn on the stage.",
                )
            }

            error?.let {
                item {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                }
            }

            // The save bar only exists once something has actually changed.
            if (hasEdits) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        TextButton(
                            enabled = !saving,
                            onClick = { draftPrompt = person.systemPrompt },
                        ) { Text("Discard") }
                        Button(
                            enabled = !saving,
                            onClick = {
                                saving = true
                                error = null
                                scope.launch {
                                    val edits = JSONObject()
                                        .put("system_prompt", draftPrompt)
                                    val failure =
                                        applyPersonaEdits(config, person.key, edits)
                                    saving = false
                                    if (failure == null) onClose(true) else error = failure
                                }
                            },
                        ) { Text(if (saving) "Saving..." else "Save") }
                    }
                }
            }
        }
    }
}
