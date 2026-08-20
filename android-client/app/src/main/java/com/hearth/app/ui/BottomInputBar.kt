package com.hearth.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.theme.HearthColors
import com.hearth.core.models.HearthState

/**
 * The voice-first bottom control, ported from the iOS `BottomInputBar`.
 *
 * The resting state is ONE button, not a split mic-plus-text-box: a capsule
 * that says what a tap will do, with a small keyboard affordance beside it
 * for typing on demand. The first Android cut had this backwards, a text
 * field with a Talk button, which made the keyboard the primary path in a
 * client whose whole point is talking.
 */
@Composable
fun BottomInputBar(
    state: HearthState,
    connected: Boolean,
    micLevel: Float,
    partialTranscript: String?,
    onTalk: () -> Unit,
    onSend: (String) -> Unit,
    onTypingChanged: (Boolean) -> Unit,
) {
    var typing by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 18.dp)
            .padding(top = 14.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // What the mic has heard so far, in its own bubble above the button
        // that will send it, with the rule written underneath: people do not
        // know a pause sends until they are told once.
        partialTranscript?.takeIf { it.isNotBlank() }?.let {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceVariant,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        it,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        "sends when you pause, or tap the button",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
        }

        if (typing) {
            TypingRow(
                onClose = {
                    typing = false
                    onTypingChanged(false)
                },
                onSend = onSend,
            )
        } else {
            TalkRow(
                state = state,
                connected = connected,
                micLevel = micLevel,
                hasWords = !partialTranscript.isNullOrBlank(),
                onTalk = onTalk,
                onKeyboard = {
                    typing = true
                    onTypingChanged(true)
                },
            )
        }
    }
}

@Composable
private fun TalkRow(
    state: HearthState,
    connected: Boolean,
    micLevel: Float,
    hasWords: Boolean,
    onTalk: () -> Unit,
    onKeyboard: () -> Unit,
) {
    // The glow rides the ACTUAL microphone, so a muted mic and a dead audio
    // route look different from a working one. A fixed pulse looked identical
    // either way, which is the bug this replaced on iOS.
    val listening = state == HearthState.LISTENING
    val scale by animateFloatAsState(
        targetValue = if (listening) 1.02f + micLevel * 0.05f else 1f,
        label = "talkScale",
    )

    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Button(
            onClick = onTalk,
            // SPEAKING is enabled on purpose: the mic mid-reply is barge-in.
            // Only THINKING is dead, because there is nothing to interrupt yet.
            enabled = connected &&
                state != HearthState.THINKING &&
                state != HearthState.LOADING,
            shape = RoundedCornerShape(percent = 50),
            colors = ButtonDefaults.buttonColors(
                containerColor = when (state) {
                    HearthState.LISTENING -> HearthColors.honey
                    HearthState.SPEAKING -> HearthColors.ember
                    else -> HearthColors.fennec
                },
                contentColor = HearthColors.roast,
            ),
            modifier = Modifier
                .widthIn(min = 200.dp, max = 240.dp)
                .scale(scale),
        ) {
            Icon(
                talkIcon(state),
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                talkLabel(state, hasWords),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(vertical = 6.dp),
            )
        }

        // The only thing flanking the talk button: the whole stage is three
        // gestures, and everything else lives in the house shelf.
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            IconButton(onClick = onKeyboard) {
                Icon(
                    Icons.Outlined.Keyboard,
                    contentDescription = "Type a message",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * The label is the contract: once there are words, a tap SENDS them (a pause
 * sends on its own). Discarding is the stage tap, not this button.
 */
private fun talkIcon(state: HearthState) = when (state) {
    HearthState.LISTENING -> Icons.Outlined.GraphicEq
    HearthState.THINKING -> Icons.Outlined.MoreHoriz
    HearthState.SPEAKING -> Icons.AutoMirrored.Outlined.VolumeUp
    else -> Icons.Outlined.Mic
}

private fun talkLabel(state: HearthState, hasWords: Boolean): String = when (state) {
    HearthState.LISTENING -> if (hasWords) "Tap to send" else "Listening"
    HearthState.THINKING -> "Thinking"
    HearthState.SPEAKING -> "Tap to interrupt"
    else -> "Tap to talk"
}

@Composable
private fun TypingRow(onClose: () -> Unit, onSend: (String) -> Unit) {
    var draft by remember { mutableStateOf("") }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TextButton(onClick = onClose) { Text("Close") }
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            placeholder = { Text("Say something") },
            modifier = Modifier.weight(1f),
            maxLines = 4,
        )
        TextButton(
            enabled = draft.isNotBlank(),
            onClick = {
                onSend(draft)
                draft = ""
            },
        ) { Text("Send") }
    }
}
