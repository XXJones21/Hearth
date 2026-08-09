import { useCallback, useEffect, useRef, useState } from 'react';
import {
  closePairing,
  explain,
  listDevices,
  openPairing,
  relativeTime,
  revokeDevice,
  type PairedDevice,
} from '../../lib/pairingApi';
import { Btn, Row } from './controls';

/* Pairing, and the devices already let in.
 *
 * Lives under Connection because that is the question it answers: which
 * devices, other than this one, can reach this house. The gateway faces the
 * LAN now so a phone can be a client, and everything arriving from off this
 * machine has to present a token it got here.
 *
 * The code is shown for five minutes and dies on use. The countdown is not
 * decoration: a code with no visible life left is a code someone will read out
 * of a stale screen and blame the phone when it fails.
 */

export function PairedDevices() {
  const [devices, setDevices] = useState<PairedDevice[] | null>(null);
  const [code, setCode] = useState<string | null>(null);
  const [remaining, setRemaining] = useState(0);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState<string | null>(null);
  /* The window is server-side state, so leaving this panel with one open would
     strand a live code on a screen nobody is looking at. */
  const openRef = useRef(false);

  const refresh = useCallback(async () => {
    const out = await listDevices();
    setDevices(out.ok ? out.value.devices : null);
  }, []);

  useEffect(() => {
    refresh();
    return () => {
      if (openRef.current) closePairing();
    };
  }, [refresh]);

  /* One second at a time, and the code disappears with the countdown rather
     than lingering as something that looks usable and is not. */
  useEffect(() => {
    if (!code) return;
    if (remaining <= 0) {
      setCode(null);
      openRef.current = false;
      setNote('That code expired. Show another when the phone is ready.');
      return;
    }
    const id = window.setTimeout(() => setRemaining((r) => r - 1), 1000);
    return () => window.clearTimeout(id);
  }, [code, remaining]);

  /* A device pairing closes the window server-side, so the poll is what turns
     the code off here and puts the phone in the list. Only while one is open. */
  useEffect(() => {
    if (!code) return;
    const id = window.setInterval(async () => {
      const out = await listDevices();
      if (!out.ok) return;
      setDevices(out.value.devices);
      if (!out.value.pairing_open) {
        setCode(null);
        openRef.current = false;
        setNote('Paired.');
      }
    }, 2000);
    return () => window.clearInterval(id);
  }, [code]);

  const show = async () => {
    setBusy(true);
    setNote('');
    const out = await openPairing();
    setBusy(false);
    if (!out.ok) {
      setNote(explain(out.why));
      return;
    }
    setCode(out.value.code);
    setRemaining(out.value.expires_in);
    openRef.current = true;
  };

  const stop = async () => {
    await closePairing();
    setCode(null);
    openRef.current = false;
  };

  const revoke = async (device: PairedDevice) => {
    setBusy(true);
    const ok = await revokeDevice(device.id);
    setBusy(false);
    setConfirming(null);
    setNote(ok ? `${device.name} can no longer reach this house.` : 'Could not revoke that device.');
    refresh();
  };

  const mmss = `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')}`;

  return (
    <>
      <Row
        label="Pair a device"
        hint="Show a code, then type it into Hearth on your phone. It lasts five minutes and works once."
      >
        {code ? (
          <Btn onClick={stop}>Stop</Btn>
        ) : (
          <Btn onClick={show} disabled={busy}>
            Show a code
          </Btn>
        )}
      </Row>

      {code && (
        <div className="mt-2 rounded-[14px] border border-linen bg-glowtint px-4 py-3 text-center">
          <div className="font-mono text-[30px] font-bold tracking-[0.32em] text-roast">
            {code}
          </div>
          <div className="mt-1 text-[11.5px] text-fawn">
            Expires in {mmss}. Enter it on the phone under Hearth's first screen.
          </div>
        </div>
      )}

      {devices && devices.length > 0 && (
        <div className="mt-2">
          {devices.map((device) => (
            <Row
              key={device.id}
              label={device.name}
              hint={`paired ${relativeTime(device.created)} · last seen ${relativeTime(
                device.last_seen,
              )}`}
            >
              {confirming === device.id ? (
                <>
                  <Btn onClick={() => setConfirming(null)}>Keep</Btn>
                  <Btn tone="warn" onClick={() => revoke(device)} disabled={busy}>
                    Unpair
                  </Btn>
                </>
              ) : (
                <Btn tone="warn" onClick={() => setConfirming(device.id)}>
                  Unpair
                </Btn>
              )}
            </Row>
          ))}
        </div>
      )}

      {devices !== null && devices.length === 0 && !code && (
        <div className="mt-2 px-1 text-[11.5px] text-fawn">
          No devices paired. This computer never needs to pair with itself.
        </div>
      )}

      {note && <div className="mt-2 px-1 text-[11.5px] text-fawn">{note}</div>}
    </>
  );
}
