package com.hearth.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.hearth.core.config.Pairing
import com.hearth.core.config.ServerConfig
import kotlinx.coroutines.launch

/**
 * First run, two steps, the same shape as the iOS `FirstRunView`: name the
 * house, then redeem the six-digit code it is showing.
 *
 * The two steps are separate because knowing where the house is and being
 * allowed through its door are different states, and a screen that conflates
 * them says "connecting" forever when the real answer is "you need to pair".
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FirstRunScreen(
    config: ServerConfig,
    reason: PairingReason = PairingReason.FIRST_RUN,
    onDone: () -> Unit,
    onTitleHold: () -> Unit = {},
) {
    var address by remember { mutableStateOf(config.address) }
    var code by remember { mutableStateOf("") }
    var step by remember { mutableStateOf(if (config.isConfigured) Step.CODE else Step.ADDRESS) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Holding the title is the appliance's way out from an UNPAIRED
        // client, which pins itself like any other and has no house button
        // to hold. Inert off the appliance, where the caller passes nothing.
        Text(
            "Hearth",
            style = MaterialTheme.typography.headlineLarge,
            modifier = Modifier.combinedClickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { },
                onLongClick = onTitleHold,
            ),
        )
        Text(
            when {
                step == Step.ADDRESS -> "Where is your house?"
                // Say WHY the phone is back here. Arriving at a code field
                // mid-session with no explanation reads as the app having lost
                // its place rather than as the house having turned you away.
                reason == PairingReason.REFUSED ->
                    "${config.address} turned this device away. Pair it again."
                else -> "Enter the code your house is showing."
            },
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp),
        )

        when (step) {
            Step.ADDRESS -> {
                OutlinedTextField(
                    value = address,
                    onValueChange = { address = it; error = null },
                    label = { Text("Address") },
                    // A tailnet name works from anywhere; a LAN address works
                    // at home. Port 18700 is assumed unless one is typed.
                    placeholder = { Text("vytal.tail22b3ca.ts.net") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        config.commitAddress(address)
                        if (config.isConfigured) {
                            step = Step.CODE
                        } else {
                            error = "Type the house's address."
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp),
                ) { Text("Continue") }
            }

            Step.CODE -> {
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.filter(Char::isDigit).take(6); error = null },
                    label = { Text("Pairing code") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    singleLine = true,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    enabled = code.length == 6 && !busy,
                    onClick = {
                        busy = true
                        error = null
                        scope.launch {
                            try {
                                Pairing.pair(config, code, android.os.Build.MODEL)
                                onDone()
                            } catch (e: Exception) {
                                error = e.message
                            } finally {
                                busy = false
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp),
                ) { Text("Pair") }

                // WHERE THE CODE COMES FROM, said on the screen that needs it.
                // /pair/open is loopback-only on purpose -- a stolen paired
                // phone must not be able to pair its thief's phone -- so the
                // code can only be shown on the machine running the house, and
                // a field labelled "Pairing code" with nothing else on the
                // screen leaves no way to find that out.
                Text(
                    "Show a code on the machine running the house: " +
                        "Settings, Connection, Pair a device. It lasts five minutes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 12.dp),
                )

                TextButton(
                    onClick = { step = Step.ADDRESS },
                    enabled = !busy,
                ) { Text("Change address") }
            }
        }

        if (busy) {
            CircularProgressIndicator(modifier = Modifier.padding(top = 16.dp))
        }

        error?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 16.dp),
            )
        }
    }
}

private enum class Step { ADDRESS, CODE }

/**
 * Why this screen is up. It changes only what the screen SAYS -- the two
 * steps and the redemption are identical -- but "pair your phone" and "your
 * house just turned this phone away" are different facts and a person acting
 * on the second one needs to be told it.
 */
enum class PairingReason {
    /** No house, or no key for it yet. */
    FIRST_RUN,

    /** There was a key and the house refused it: revoked, or a different
     *  house is answering at this address now. */
    REFUSED,
}
