package com.hearth.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * The brand, as Compose sees it. The tokens are the same hexes the iOS
 * `HearthPalette` carries and the face already draws with, so the chrome and
 * the persona cannot drift apart.
 *
 * Stock Material purple was standing in until now, which read as somebody
 * else's app around Hearth's own face.
 */
object HearthColors {
    /** mascot chest fluff -- app background */
    val cream = Color(0xFFFAF4EA)
    /** white fur -- cards and surfaces */
    val fluff = Color(0xFFFFFFFF)
    /** body fur -- primary accent, the orb */
    val fennec = Color(0xFFE39A5B)
    /** shaded fur -- hover, pressed, emphasis */
    val ember = Color(0xFFC97F45)
    /** pitch amber -- highlights, glows, fills */
    val honey = Color(0xFFFFB84D)
    /** eyes and ear tips -- primary text, the ink */
    val roast = Color(0xFF3B2B20)
    /** muted fur shadow -- secondary text */
    val fawn = Color(0xFF8C7A66)
    /** dividers and recessed tracks */
    val linen = Color(0xFFEFE6D8)
    val parchment = Color(0xFFFBF3E7)

    // The dark surfaces. iOS renders the stage on cream; a phone that lives
    // on a bedside table at night wants the roast end of the same palette
    // rather than a second, unrelated set of greys.
    val night = Color(0xFF241A14)
    val nightRaised = Color(0xFF33251C)
}

private val HearthDark = darkColorScheme(
    primary = HearthColors.honey,
    onPrimary = HearthColors.roast,
    primaryContainer = HearthColors.ember,
    onPrimaryContainer = HearthColors.cream,
    secondary = HearthColors.fennec,
    onSecondary = HearthColors.roast,
    background = HearthColors.night,
    onBackground = HearthColors.cream,
    surface = HearthColors.night,
    onSurface = HearthColors.cream,
    surfaceVariant = HearthColors.nightRaised,
    onSurfaceVariant = HearthColors.fawn,
    outline = HearthColors.fawn,
)

private val HearthLight = lightColorScheme(
    primary = HearthColors.ember,
    onPrimary = HearthColors.fluff,
    primaryContainer = HearthColors.honey,
    onPrimaryContainer = HearthColors.roast,
    secondary = HearthColors.fennec,
    onSecondary = HearthColors.roast,
    background = HearthColors.cream,
    onBackground = HearthColors.roast,
    surface = HearthColors.parchment,
    onSurface = HearthColors.roast,
    surfaceVariant = HearthColors.linen,
    onSurfaceVariant = HearthColors.fawn,
    outline = HearthColors.fawn,
)

/**
 * LIGHT by default, because that is what iOS ships to the alpha testers: the
 * stage is cream with roast ink, and a phone that renders the same house in
 * the negative is not the same product.
 *
 * The dark scheme stays for the appliance's closed lid, which is a lit face
 * in a dim room, and is selected explicitly rather than by system preference.
 */
@Composable
fun HearthTheme(dark: Boolean = false, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (dark) HearthDark else HearthLight,
        content = content,
    )
}
