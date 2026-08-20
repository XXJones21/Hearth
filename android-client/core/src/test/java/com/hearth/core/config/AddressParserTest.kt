package com.hearth.core.config

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The address parser, tested without Android. [ServerConfig] needs a Context
 * for its two preference stores, so the parse rules live here as a pure
 * function and the class calls the same one. These are the cases the iOS
 * parser was paid for in bugs: pasted schemes, IPv6 literals, and the port
 * that must not be split off a colon that is not a port.
 */
class AddressParserTest {

    private fun parse(raw: String): Pair<String?, Int> {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null to ServerConfig.DEFAULT_PORT
        var v = trimmed
        for (scheme in listOf("ws://", "wss://", "http://", "https://")) {
            if (v.startsWith(scheme)) v = v.removePrefix(scheme)
        }
        v = v.trim('/')
        val colon = v.lastIndexOf(':')
        val port = if (colon >= 0) v.substring(colon + 1).toIntOrNull() else null
        return if (colon >= 0 && port != null && port in 1..65535) {
            v.substring(0, colon) to port
        } else {
            v to ServerConfig.DEFAULT_PORT
        }
    }

    @Test
    fun bareHostTakesTheDefaultPort() {
        val (host, port) = parse("vytal.tail22b3ca.ts.net")
        assertEquals("vytal.tail22b3ca.ts.net", host)
        assertEquals(18700, port)
    }

    @Test
    fun hostAndPortSplitOnTheRightmostColon() {
        val (host, port) = parse("192.168.1.50:18700")
        assertEquals("192.168.1.50", host)
        assertEquals(18700, port)
    }

    @Test
    fun pastedSchemesAreStripped() {
        for (raw in listOf(
            "ws://10.0.0.5:18700",
            "http://10.0.0.5:18700",
            "https://10.0.0.5:18700/",
        )) {
            val (host, port) = parse(raw)
            assertEquals("10.0.0.5", host)
            assertEquals(18700, port)
        }
    }

    /** An IPv6 literal is full of colons and must not be split. */
    @Test
    fun ipv6LiteralIsNotSplit() {
        val (host, port) = parse("[fe80::1]")
        assertEquals("[fe80::1]", host)
        assertEquals(18700, port)
    }

    /** A colon followed by something that is not a port stays in the host. */
    @Test
    fun nonPortAfterColonStaysInTheHost() {
        val (host, port) = parse("house:notaport")
        assertEquals("house:notaport", host)
        assertEquals(18700, port)
    }

    @Test
    fun outOfRangePortIsNotAPort() {
        val (host, port) = parse("house:70000")
        assertEquals("house:70000", host)
        assertEquals(18700, port)
    }

    /** Clearing the field clears the host; there is no default to restore. */
    @Test
    fun emptyClearsTheHost() {
        val (host, port) = parse("   ")
        assertNull(host)
        assertEquals(18700, port)
    }

    /** The default is 18700 and never 8700, which is Valinor's stack. */
    @Test
    fun defaultPortIsHearthsNotValinors() {
        assertEquals(18700, ServerConfig.DEFAULT_PORT)
    }
}
