package com.hearth.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.persona.PersonaFace
import com.hearth.core.models.ChatMessage
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.face.FaceGeometry

/**
 * The stage, shaped like the iOS `HearthMainView`: the persona occupies the
 * top, the timeline runs beneath it, and one composer sits at the bottom.
 *
 * The persona area is a placeholder until phase 3 brings the Compose face;
 * the LAYOUT is the part that matters now, because phase 3 fills this box
 * rather than rearranging the screen.
 */
@Composable
fun HearthMainScreen(
    state: HearthState,
    connected: Boolean,
    personaName: String,
    thinkingStage: String?,
    messages: List<ChatMessage>,
    palette: PersonaPalette,
    faceGeometry: FaceGeometry?,
    faceCue: Pair<String, Long>?,
    caption: String?,
    audioLevel: Float,
    partialTranscript: String?,
    onSend: (String) -> Unit,
    onMic: () -> Unit,
) {
    // The IME resizes the whole stage, not just the composer: padding an
    // inner row instead squeezes the timeline to nothing while the keyboard
    // is up, which reads as a client that lost the conversation.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .navigationBarsPadding()
            .statusBarsPadding()
    ) {

        // ---- the stage: persona plus status ----
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(0.38f),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // A procedural_face persona draws its face; anything else
                // keeps the orb, the same fallback contract iOS uses.
                if (faceGeometry != null) {
                    PersonaFace(
                        geometry = faceGeometry,
                        state = state,
                        palette = palette,
                        speechLevel = audioLevel,
                        cue = faceCue,
                        modifier = Modifier.size(180.dp),
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .size((140 + (audioLevel * 30f)).dp)
                            .clip(CircleShape)
                            .background(
                                if (connected) MaterialTheme.colorScheme.primaryContainer
                                else MaterialTheme.colorScheme.surfaceVariant
                            )
                    )
                }
                Text(
                    personaName,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 12.dp),
                )
                Text(
                    statusLine(state, connected, thinkingStage),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                // The karaoke caption: the sentence being HEARD right now,
                // released by playback position rather than arrival.
                caption?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                    )
                }

                // What the mic has heard so far, while it is still hearing it.
                partialTranscript?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                    )
                }
            }
        }

        // ---- the timeline ----
        val listState = rememberLazyListState()
        LaunchedEffect(messages.size) {
            if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
        }
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxWidth()
                .weight(0.62f),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(messages, key = { it.id }) { MessageRow(it) }
        }

        Composer(state = state, onSend = onSend, onMic = onMic)
    }
}

@Composable
private fun MessageRow(message: ChatMessage) {
    val isUser = message.role == ChatMessage.Role.USER
    val isSystem = message.role == ChatMessage.Role.SYSTEM
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = when {
                isSystem -> Color.Transparent
                isUser -> MaterialTheme.colorScheme.primaryContainer
                else -> MaterialTheme.colorScheme.surfaceVariant
            },
        ) {
            Text(
                message.text,
                style = if (isSystem) MaterialTheme.typography.bodySmall
                else MaterialTheme.typography.bodyMedium,
                color = if (isSystem) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
    }
}

/**
 * One composer, as on iOS. The voice button arrives with phase 2; today the
 * text field is the whole turn.
 */
@Composable
private fun Composer(
    state: HearthState,
    onSend: (String) -> Unit,
    onMic: () -> Unit,
) {
    var draft by remember { mutableStateOf("") }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            placeholder = { Text("Say something") },
            modifier = Modifier.weight(1f),
            maxLines = 4,
        )
        if (draft.isNotBlank()) {
            TextButton(
                onClick = {
                    onSend(draft)
                    draft = ""
                },
            ) { Text("Send") }
        } else {
            // The mic is the primary affordance, as on iOS: "Tap to talk"
            // with the keyboard as the secondary path. During SPEAKING it is
            // barge-in, and during LISTENING it commits early.
            TextButton(onClick = onMic) {
                Text(
                    when (state) {
                        HearthState.LISTENING -> "Stop"
                        HearthState.SPEAKING -> "Interrupt"
                        else -> "Talk"
                    }
                )
            }
        }
    }
}

/** The house's own language for what it is doing, as the iOS status bar does. */
private fun statusLine(state: HearthState, connected: Boolean, stage: String?): String {
    if (!connected) return "Not connected"
    return when (state) {
        HearthState.LOADING -> "Waking the house"
        HearthState.IDLE -> "Ready"
        HearthState.LISTENING -> "Listening"
        HearthState.THINKING -> when (stage) {
            "transcribing" -> "Catching that"
            "deciding" -> "Thinking it through"
            "acting" -> "Working on it"
            else -> "Thinking"
        }
        HearthState.SPEAKING -> "Speaking"
    }
}
