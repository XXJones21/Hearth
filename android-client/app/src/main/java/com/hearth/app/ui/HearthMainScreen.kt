package com.hearth.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.platform.LocalDensity
import com.hearth.app.ui.cards.DynamicCard
import com.hearth.app.ui.persona.PersonaFace
import com.hearth.app.ui.persona.PersonaFlame
import com.hearth.app.ui.persona.PersonaOrb
import com.hearth.core.cards.CardDescriptor
import com.hearth.core.models.ChatMessage
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.PersonaForm
import com.hearth.core.persona.face.FaceGeometry
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The unified portrait scene, ported from the iOS `HearthMainView`. One
 * continuous layout in two states:
 *
 *   COLLAPSED (the default): the stage owns everything above the composer.
 *     The conversation IS the persona, its caption and its voice.
 *   EXPANDED: the stage takes the upper 45 percent and yields the rest to the
 *     timeline.
 *
 * The persona is never covered in either state; it keeps whatever slack is
 * left after the caption takes the height it needs.
 *
 * The stage is a tap target with three meanings, which is why it is NOT the
 * same gesture as the talk button:
 *   SPEAKING   quiet the voice without opening the mic
 *   LISTENING  throw the partial away
 *   IDLE       start a turn
 */
@Composable
fun HearthMainScreen(
    state: HearthState,
    connected: Boolean,
    personaName: String,
    activeTools: List<String>,
    messages: List<ChatMessage>,
    palette: PersonaPalette,
    faceGeometry: FaceGeometry?,
    personaForm: PersonaForm,
    faceCue: Pair<String, Long>?,
    caption: String?,
    cards: List<CardDescriptor>,
    ttsAmplitude: Float,
    micLevel: Float,
    partialTranscript: String?,
    transcriptShown: Boolean,
    onChoice: (String) -> Unit,
    onSend: (String) -> Unit,
    onTalk: () -> Unit,
    onStageTap: () -> Unit,
    onShelf: () -> Unit,
) {
    var composerUp by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .navigationBarsPadding()
                .statusBarsPadding()
        ) {
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(if (transcriptShown) 0.45f else 1f)
                    // No ripple: the stage is a surface you touch, not a button.
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onStageTap,
                    )
            ) {
                val stageHeightPx = constraints.maxHeight.toFloat()
                PersonaStage(
                    stageHeightPx = stageHeightPx,
                    // Collapsed, the stage is the ONLY surface, so the newest
                    // card stays put after the turn ends. Expanded, the feed
                    // below is holding it and two copies on one screen is the
                    // redundancy iOS removed.
                    stageCard = cards.lastOrNull(),
                    onChoice = onChoice,
                    state = state,
                    connected = connected,
                    palette = palette,
                    faceGeometry = faceGeometry,
                    personaForm = personaForm,
                    faceCue = faceCue,
                    caption = caption,
                    ttsAmplitude = ttsAmplitude,
                    composerUp = composerUp,
                    transcriptShown = transcriptShown,
                )
            }

            AnimatedVisibility(visible = transcriptShown) {
                Timeline(
                    messages = messages,
                    cards = cards,
                    onChoice = onChoice,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            HouseStatusBar(
                state = state,
                personaName = personaName,
                activeTools = activeTools,
            )

            BottomInputBar(
                state = state,
                connected = connected,
                micLevel = micLevel,
                partialTranscript = partialTranscript,
                onTalk = onTalk,
                onSend = onSend,
                onTypingChanged = { composerUp = it },
            )
        }

        // The house lives behind one affordance in the top corner, as on iOS:
        // a hamburger, not a word.
        IconButton(
            onClick = onShelf,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(4.dp),
        ) {
            Icon(
                Icons.Outlined.Menu,
                contentDescription = "House",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Persona on top keeping the slack, the caption below taking exactly the
 * height it needs. Stacked rather than overlaid: overlaying let a tall
 * caption bury the persona, and the persona being visible at all times is the
 * whole point of the stage.
 */
@Composable
private fun PersonaStage(
    stageHeightPx: Float,
    stageCard: CardDescriptor?,
    onChoice: (String) -> Unit,
    state: HearthState,
    connected: Boolean,
    palette: PersonaPalette,
    faceGeometry: FaceGeometry?,
    personaForm: PersonaForm,
    faceCue: Pair<String, Long>?,
    caption: String?,
    ttsAmplitude: Float,
    composerUp: Boolean,
    transcriptShown: Boolean,
) {
    val isIdle = state == HearthState.IDLE || state == HearthState.LOADING

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentAlignment = Alignment.Center,
        ) {
            // Sized against the SMALLER dimension of the space it is given, so
            // the inner display, the cover screen and a tablet all work. A
            // fixed dp was written against one emulator and looked wrong on
            // the first real device.
            BoxWithConstraints(contentAlignment = Alignment.Center) {
                val side = minOf(maxWidth, maxHeight) * 0.82f
                // THE RENDERER IS CHOSEN FROM THE PERSONA'S OWN CONFIG, never
                // by name. A form whose numbers or assets have not arrived
                // falls back to the orb rather than showing nothing -- the same
                // contract every other client keeps, and what lets Sage arrive
                // with no code change here.
                if (personaForm == PersonaForm.FLAME) {
                    PersonaFlame(
                        state = state,
                        pulse = ttsAmplitude,
                        faceGeometry = faceGeometry,
                        palette = palette,
                        faceCue = faceCue,
                        composerUp = composerUp,
                        modifier = Modifier.size(side),
                    )
                } else if (personaForm == PersonaForm.PROCEDURAL_FACE && faceGeometry != null) {
                    PersonaFace(
                        geometry = faceGeometry,
                        state = state,
                        palette = palette,
                        speechLevel = ttsAmplitude,
                        cue = faceCue,
                        composerUp = composerUp,
                        modifier = Modifier.size(side),
                    )
                } else {
                    // A persona whose face numbers have not arrived falls back
                    // to its orb rather than showing nothing, the same contract
                    // iOS uses for a model with no clips. It was a flat filled
                    // circle until 2026-08-20, which is indistinguishable from
                    // a rendering failure.
                    PersonaOrb(
                        state = state,
                        pulse = ttsAmplitude,
                        palette = palette,
                        modifier = Modifier.size(side),
                    )
                }
            }

            // The clock crowns an idle stage. It shares the screen with the
            // last reply quite happily: the iOS stage at rest shows the clock
            // above the persona AND the caption below it. What displaces the
            // clock is a CARD, not a caption.
            if (isIdle && stageCard == null) {
                IdleClock(modifier = Modifier.align(Alignment.TopCenter))
            }
        }

        // The card takes a bounded share and scrolls inside it. It must never
        // take so much that the persona is squeezed out: the visualization is
        // the point of the stage and stays visible at all times.
        if (stageCard != null) {
            val ceiling = with(LocalDensity.current) {
                (stageHeightPx * (if (transcriptShown) 0.34f else 0.46f)).toDp()
            }
            Column(
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .widthIn(max = 460.dp)
                    .heightIn(max = ceiling)
                    .verticalScroll(rememberScrollState()),
            ) {
                DynamicCard(card = stageCard, onChoice = onChoice)
            }
        }

        // The caption band: the reply so far, filling at the pace of the
        // VOICE, bounded so it stays a caption sharing the stage rather than
        // becoming a second transcript.
        if (!caption.isNullOrBlank()) {
            val ceilingPx = stageHeightPx * (if (transcriptShown) 0.30f else 0.36f)
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                border = androidx.compose.foundation.BorderStroke(
                    1.dp,
                    MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                ),
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .widthIn(max = 520.dp),
            ) {
                Text(
                    caption,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                    // Roughly a line per 19pt of the ceiling, as on iOS.
                    maxLines = captionLines(ceilingPx),
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                )
            }
        }
    }
}

private fun captionLines(ceilingPx: Float): Int =
    (ceilingPx / 52f).toInt().coerceIn(2, 12)

@Composable
private fun IdleClock(modifier: Modifier = Modifier) {
    val now by produceState(initialValue = Date()) {
        while (true) {
            value = Date()
            delay(20_000)
        }
    }
    Column(
        modifier = modifier.padding(top = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            remember(now) { SimpleDateFormat("h:mm", Locale.getDefault()).format(now) },
            style = MaterialTheme.typography.displayMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
            remember(now) { SimpleDateFormat("EEEE, MMM d", Locale.getDefault()).format(now) },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** One row of the feed: a spoken line or a card the house drew. */
private sealed interface FeedEntry {
    val at: Long
    val key: String

    data class Line(val message: ChatMessage) : FeedEntry {
        override val at get() = message.timestamp
        override val key get() = "m-${message.id}"
    }

    data class Card(val card: CardDescriptor) : FeedEntry {
        override val at get() = card.receivedAt
        override val key get() = "c-${card.id}"
    }
}

@Composable
private fun Timeline(
    messages: List<ChatMessage>,
    cards: List<CardDescriptor>,
    onChoice: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Messages and cards INTERLEAVED by arrival, as iOS does: a card belongs
    // where it happened in the conversation, not in a separate tray.
    val feed = remember(messages, cards) {
        (messages.map(FeedEntry::Line) + cards.map(FeedEntry::Card))
            .sortedBy { it.at }
    }
    val listState = rememberLazyListState()
    LaunchedEffect(feed.size) {
        if (feed.isNotEmpty()) listState.animateScrollToItem(feed.lastIndex)
    }
    LazyColumn(
        state = listState,
        modifier = modifier.heightIn(max = 600.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(feed, key = { it.key }) { entry ->
            when (entry) {
                is FeedEntry.Line -> MessageRow(entry.message)
                is FeedEntry.Card -> DynamicCard(entry.card, onChoice = onChoice)
            }
        }
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
