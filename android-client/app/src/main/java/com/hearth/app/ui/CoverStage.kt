package com.hearth.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.cards.DynamicCard
import com.hearth.app.ui.persona.PersonaFace
import com.hearth.app.ui.persona.PersonaFlame
import com.hearth.app.ui.persona.PersonaOrb
import com.hearth.core.cards.CardDescriptor
import com.hearth.core.models.HearthState
import com.hearth.core.persona.PersonaForm
import com.hearth.core.persona.PersonaPalette
import com.hearth.core.persona.face.FaceGeometry
import kotlinx.coroutines.delay

/**
 * The stage on the cover screen.
 *
 * The Razr's outer display is a REAL second display -- 1056x1066 at 360dpi,
 * its own display group, flagged for presentation -- so the client runs there
 * unmodified rather than needing a widget. What it needed was a layout: the
 * inner display is 2640 tall and this is barely a square, and Motorola's own
 * chrome owns the bottom quarter of it, so the app gets a landscape-ish strip
 * roughly 469 x 344dp.
 *
 * Two things follow, and they are the whole difference from [PersonaStage]:
 *
 * **The persona MOVES rather than sharing.** On the tall display the clock
 * crowns the stage, the persona keeps the slack and the caption sits below it,
 * all at once. Here there is not room for all at once: overlaid, the clock
 * lands on the persona's face. So the persona rides between the middle of an
 * empty stage and the top of a busy one, and the animation between those is
 * what makes it read as one surface rearranging rather than two layouts
 * swapping.
 *
 * **The caption expires.** A reply that stays up forever holds the persona in
 * its raised position forever, which on a screen this size means the stage
 * never returns to rest. Thirty seconds after the house stops talking, if
 * nothing follows, the caption goes and the persona settles back to centre.
 *
 * The expiry is deliberately NOT in the ViewModel: the inner display shows the
 * last reply at rest on purpose, matching iOS, and it has the room to. This is
 * a fact about a small screen, not about the conversation.
 */
@Composable
fun CoverStage(
    state: HearthState,
    palette: PersonaPalette,
    faceGeometry: FaceGeometry?,
    personaForm: PersonaForm,
    faceCue: Pair<String, Long>?,
    caption: String?,
    card: CardDescriptor?,
    ttsAmplitude: Float,
    onChoice: (String) -> Unit,
) {
    // What the caption looks like to THIS screen: present until it goes stale.
    // Keyed on the text so a new reply always arrives visible, and on the state
    // so the countdown restarts when a turn begins.
    var captionFresh by remember { mutableStateOf(true) }
    LaunchedEffect(caption, state) {
        if (caption.isNullOrBlank()) return@LaunchedEffect
        captionFresh = true
        // Only run the clock once the house has stopped talking. Counting
        // during the reply would expire a long answer while it was still
        // being spoken.
        if (state == HearthState.IDLE) {
            delay(CAPTION_LIFE_MS)
            captionFresh = false
        }
    }

    val showCaption = !caption.isNullOrBlank() && captionFresh
    val busy = showCaption || card != null

    // -1 is the top of the box, 0 its middle. The persona rides between them
    // rather than being re-parented, so nothing about it is torn down and
    // rebuilt -- the flame keeps its clock and the face keeps its director
    // across the move.
    val bias by animateFloatAsState(
        targetValue = if (busy) -1f else 0f,
        animationSpec = tween(durationMillis = 420),
        label = "personaRise",
    )
    // A FLOOR, not a fraction. Busy on this screen can mean caption AND card
    // AND a live partial transcript at once, and each band takes its height
    // before the persona takes what is left -- which on the first device run
    // squeezed the fire to a thumbnail. The persona is the point of the stage
    // and keeps most of it.
    val personaShare by animateFloatAsState(
        targetValue = if (busy) 0.62f else 1f,
        animationSpec = tween(durationMillis = 420),
        label = "personaShare",
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .weight(personaShare.coerceAtLeast(0.05f)),
            contentAlignment = BiasAlignment(0f, bias),
        ) {
            // Sized against the SHORT side, which on this display is the
            // height and on the inner one is the width. A persona measured
            // against the width here would not fit the strip it lives in.
            val side = minOf(maxWidth, maxHeight) * 0.92f
            when {
                personaForm == PersonaForm.FLAME -> PersonaFlame(
                    state = state,
                    pulse = ttsAmplitude,
                    faceGeometry = faceGeometry,
                    palette = palette,
                    faceCue = faceCue,
                    modifier = Modifier.size(side),
                )

                personaForm == PersonaForm.PROCEDURAL_FACE && faceGeometry != null ->
                    PersonaFace(
                        geometry = faceGeometry,
                        state = state,
                        palette = palette,
                        speechLevel = ttsAmplitude,
                        cue = faceCue,
                        modifier = Modifier.size(side),
                    )

                else -> PersonaOrb(
                    state = state,
                    pulse = ttsAmplitude,
                    palette = palette,
                    modifier = Modifier.size(side),
                )
            }

            // NO CLOCK HERE, and the device is why. Motorola draws its own
            // clock in the pill directly below this window, so ours was the
            // second one on the same screen -- and at the top of a strip this
            // short it was clipped by the edge and had the flame's embers
            // rising through it. The stage gives the persona the whole space
            // and lets the OS keep the time.
        }

        // A card takes a bounded share and scrolls inside it. The timer is the
        // strongest case for a card on a closed phone -- a countdown you can
        // read without opening it -- and a dashboard is the weakest, so the
        // ceiling is deliberately tight.
        if (card != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 132.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 6.dp),
            ) {
                DynamicCard(card = card, onChoice = onChoice)
            }
        }

        if (showCaption) {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                border = BorderStroke(
                    1.dp,
                    MaterialTheme.colorScheme.outline.copy(alpha = 0.35f),
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 6.dp),
            ) {
                Text(
                    caption.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                    // Four lines on this screen is already half the stage.
                    // Past that the reply belongs to the inner display.
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }
        }
    }
}

/** Thirty seconds of nothing following, and the stage returns to rest. */
private const val CAPTION_LIFE_MS = 30_000L

/**
 * Below this, the client is on the cover screen rather than the inner one.
 *
 * Measured rather than guessed: the inner display gives the stage about
 * 1005dp of height and the cover about 344dp once Motorola's chrome has taken
 * its share. Anything in between is a tablet or a split-screen window, and
 * those want the tall layout.
 */
val CoverHeightThreshold = 520.dp

/** True when [Box] is a cover-sized strip rather than a phone-sized stage. */
@Composable
fun isCoverSized(heightDp: androidx.compose.ui.unit.Dp): Boolean =
    heightDp < CoverHeightThreshold
