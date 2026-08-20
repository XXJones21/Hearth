package com.hearth.app.ui.surfaces

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.theme.HearthColors
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.PersonaEntry
import com.hearth.core.surfaces.PersonaSurface
import com.hearth.core.surfaces.applyPersonaEdits
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Who lives here, ported from the iOS `PersonaView`.
 *
 * One screen with an avatar picker across the top rather than a list that
 * opens detail pages: there are two or three personas, and comparing them is
 * the common act.
 *
 * The sections are in the desktop's order because the order is the argument:
 * who they are, then how they are (the prompt, which IS the persona), then
 * voice and presence. Everything carries a lock except the prompt, and the
 * prompt is batched behind Save. Nothing writes on a keystroke: a persona is
 * hours of writing and an autosave turns a stray tap into a permanent edit.
 */
@Composable
fun PersonaScreen(config: ServerConfig, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<PersonaSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    var selectedKey by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        surface = PersonaSurface.load(config)
        loading = false
    }

    val people = surface?.personas?.filterNot { it.internal }.orEmpty()
    val person = people.firstOrNull { it.key == selectedKey } ?: people.firstOrNull()

    SurfaceBackground {
        LazyColumn {
            item { SurfaceTopBar(onBack = onBack) }
            item { SurfaceTitle("Who lives here") }

            when {
                loading -> item { SurfaceLoadingBlock() }
                person == null -> item { SurfaceUnavailableBlock() }
                else -> {
                    item {
                        Row(
                            modifier = Modifier
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = 20.dp, vertical = 10.dp),
                            horizontalArrangement = Arrangement.spacedBy(18.dp),
                        ) {
                            for (candidate in people) {
                                Avatar(
                                    person = candidate,
                                    selected = candidate.key == person.key,
                                    onClick = {
                                        selectedKey = candidate.key
                                        editing = false
                                    },
                                )
                            }
                        }
                    }

                    item { SectionHeading("Who they are") }
                    item {
                        GroupCard {
                            FieldRow("Name", person.name)
                            RowDivider()
                            FieldRow("Description", person.description)
                            RowDivider()
                            FieldRow(
                                "Classification",
                                person.classification.ifBlank { "unset" },
                            )
                        }
                    }

                    item { SectionHeading("How they are", "this is the persona") }
                    item {
                        PromptBlock(
                            config = config,
                            person = person,
                            editing = editing,
                            onEdit = { editing = true },
                            onDone = { changed ->
                                editing = false
                                if (changed) {
                                    loading = true
                                    surface = null
                                }
                            },
                        )
                    }

                    item { SectionHeading("Voice") }
                    item {
                        GroupCard {
                            FieldRow(
                                "Manner",
                                person.voiceManner.ifBlank { "unset" },
                            )
                            RowDivider()
                            FieldRow(
                                "Clip",
                                person.voiceClip.ifBlank { "No clone" },
                            )
                            if (person.voiceLine.isNotBlank()) {
                                RowDivider()
                                FieldRow("What the clip says", person.voiceLine)
                            }
                        }
                    }

                    item { SectionHeading("Presence") }
                    item {
                        GroupCard {
                            FieldRow("Form", person.form.ifBlank { "orb" })
                        }
                    }

                    item {
                        SurfaceFootnote(
                            "The prompt is this phone's to change. Everything else " +
                                "about a persona is edited at the desk.",
                        )
                    }
                }
            }
        }
    }

    // Reload after a save so the page shows what the house now holds.
    LaunchedEffect(loading, surface) {
        if (loading && surface == null) {
            surface = PersonaSurface.load(config)
            loading = false
        }
    }
}

@Composable
private fun Avatar(person: PersonaEntry, selected: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(66.dp)
                .clip(CircleShape)
                .background(if (selected) HearthColors.ember else HearthColors.honey)
                .then(
                    if (selected) Modifier.border(2.dp, HearthColors.honey, CircleShape)
                    else Modifier
                )
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                person.name.take(2),
                style = MaterialTheme.typography.titleMedium,
                color = if (selected) HearthColors.cream else HearthColors.roast,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            person.name,
            style = MaterialTheme.typography.labelMedium,
            color = if (selected) MaterialTheme.colorScheme.onBackground
            else MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

/**
 * The prompt: shown truncated with its size underneath, opened for editing
 * only when asked, and written only on Save.
 */
@Composable
private fun PromptBlock(
    config: ServerConfig,
    person: PersonaEntry,
    editing: Boolean,
    onEdit: () -> Unit,
    onDone: (Boolean) -> Unit,
) {
    var draft by remember(person.key) { mutableStateOf(person.systemPrompt) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val hasEdits = draft != person.systemPrompt

    Column {
        GroupCard {
            if (editing) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = {
                        draft = it
                        error = null
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 260.dp)
                        .padding(12.dp),
                )
            } else {
                Text(
                    person.systemPrompt,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 10,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .clickable(onClick = onEdit)
                        .padding(16.dp),
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "%,d characters".format(draft.length),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!editing) {
                Text(
                    "Tap to edit",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.clickable(onClick = onEdit),
                )
            }
        }

        error?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 20.dp),
            )
        }

        if (editing) {
            Row(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(
                    enabled = !saving,
                    onClick = {
                        draft = person.systemPrompt
                        onDone(false)
                    },
                ) { Text("Discard") }
                Button(
                    enabled = !saving && hasEdits,
                    onClick = {
                        saving = true
                        error = null
                        scope.launch {
                            val edits = JSONObject().put("system_prompt", draft)
                            val failure = applyPersonaEdits(config, person.key, edits)
                            saving = false
                            if (failure == null) onDone(true) else error = failure
                        }
                    },
                ) { Text(if (saving) "Saving..." else "Save") }
            }
        }
    }
}
