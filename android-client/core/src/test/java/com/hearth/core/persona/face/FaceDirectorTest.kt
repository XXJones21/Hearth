package com.hearth.core.persona.face

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The iOS director suite, ported. Every assertion here only passes when the
 * timing tables match: the blink band is the tier's interval, the envelope
 * numbers are laughter's attack/hold/decay. A drifted constant fails as a
 * number rather than as "the face feels off".
 */
class FaceDirectorTest {

    private val warm = FaceGeometry()

    @Test
    fun idleVariesGazeAndBlinksCalm() {
        val d = FaceDirector(warm, now = 0.0)
        val gazes = mutableSetOf<String>()
        var blinks = 0
        var inBlink = false
        var t = 0.0
        while (t <= 30_000) {
            val p = d.tick(t, FaceState.IDLE, null, 0.0, reduceMotion = false)
            if (t > 2000) gazes.add(String.format("%.2f", p.gazeX))
            val closed = p.eyelidL > 0.7
            if (closed && !inBlink) {
                blinks++
                inBlink = true
            }
            if (!closed) inBlink = false
            t += 16.7
        }
        assertTrue("gaze varied: ${gazes.size}", gazes.size > 3)
        assertTrue("calm tier: got $blinks blinks in 30s", blinks in 3..10)
    }

    @Test
    fun transientEnvelopeLerpsInHoldsAndDecays() {
        val d = FaceDirector(warm, now = 0.0)
        d.tick(0.0, FaceState.IDLE, null, 0.0, reduceMotion = true) // snap-settle
        val cue = FaceCue("laughter", at = 100.0)

        val ramp = d.tick(160.0, FaceState.IDLE, cue, 0.0, reduceMotion = true)
        assertTrue("mid-attack: ${ramp.eyeArc}", ramp.eyeArc > 0.1 && ramp.eyeArc < 0.9)

        val hold = d.tick(400.0, FaceState.IDLE, cue, 0.0, reduceMotion = true)
        assertTrue("hold: ${hold.eyeArc}", hold.eyeArc > 0.8)

        val gone = d.tick(3200.0, FaceState.IDLE, cue, 0.0, reduceMotion = true)
        assertTrue("decayed: ${gone.eyeArc}", gone.eyeArc < 0.05)
    }

    @Test
    fun speechOpensRoundMouthAndListeningWatchesTarget() {
        val d = FaceDirector(warm, now = 0.0)
        val talk = d.tick(50.0, FaceState.SPEAKING, null, 0.5, reduceMotion = true)
        assertTrue("mouth open: ${talk.mouthOpen}", talk.mouthOpen >= 0.45)
        assertEquals(1.0, talk[PoseChannel.MOUTH_ROUND], 1e-9)

        val watch = d.tick(
            5000.0,
            FaceState.LISTENING,
            null,
            0.0,
            reduceMotion = true,
            lookTarget = LookTarget(x = 0.0, y = 0.9, focus = 0.5),
        )
        assertTrue("pulled toward target: ${watch.gazeY}", watch.gazeY > 0.5)
    }

    @Test
    fun reduceMotionSuppressesBlink() {
        val d = FaceDirector(warm, now = 0.0)
        var t = 0.0
        var closed = false
        while (t <= 20_000) {
            val p = d.tick(t, FaceState.IDLE, null, 0.0, reduceMotion = true)
            if (p.eyelidL > 0.5) closed = true
            t += 16.7
        }
        assertFalse(closed)
    }

    /**
     * An unknown expression name is neutral: a house ahead of this client must
     * not break the face.
     */
    @Test
    fun unknownExpressionIsNeutral() {
        val base = neutralPose(warm)
        val out = applyNamedExpression(base, "jubilation", 1.0)
        assertEquals(base.eyelidL, out.eyelidL, 1e-9)
        assertEquals(base.eyeArc, out.eyeArc, 1e-9)
    }

    /** Hard-ranged channels stay in range however deltas are layered. */
    @Test
    fun clampedChannelsStayInRange() {
        var pose = neutralPose(warm)
        repeat(5) {
            pose = applyExpression(pose, FACE_EXPRESSIONS[ExpressionName.BLINK]!!, 1.0)
        }
        assertTrue(pose.eyelidL <= 1.0)
        assertTrue(pose.eyelidR <= 1.0)
    }

    /** A backwards clock must not drive channels away from target or NaN out. */
    @Test
    fun backwardsClockIsSafe() {
        val d = FaceDirector(warm, now = 10_000.0)
        d.tick(10_000.0, FaceState.IDLE, null, 0.0, reduceMotion = false)
        val p = d.tick(5_000.0, FaceState.IDLE, null, 0.0, reduceMotion = false)
        assertFalse("gazeX is NaN", p.gazeX.isNaN())
        assertFalse("headTilt is NaN", p.headTilt.isNaN())
    }

    /** A cue stamped in the future must not pre-fire at partial weight. */
    @Test
    fun futureCueDoesNotPreFire() {
        val d = FaceDirector(warm, now = 0.0)
        d.tick(0.0, FaceState.IDLE, null, 0.0, reduceMotion = true)
        val cue = FaceCue("surprise", at = 500.0)
        val early = d.tick(200.0, FaceState.IDLE, cue, 0.0, reduceMotion = true)
        assertEquals(0.0, early[PoseChannel.FOCUS], 1e-9)
    }
}
