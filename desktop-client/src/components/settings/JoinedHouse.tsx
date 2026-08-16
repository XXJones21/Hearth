import { useState } from 'react';
import { getHttpOrigin } from '../../lib/config';
import { claim } from '../../lib/pairingApi';
import { deviceName as machineName, hasProbe } from '../../lib/probe';
import { loadSettings, saveSettings } from '../../lib/settings';
import { Btn, Row } from './controls';

/* The Connection panel, seen from a machine that joined someone else's house.
 *
 * The device list is not shown here and cannot be: the management routes are
 * refused from off the machine even with a valid token, precisely so a stolen
 * device cannot pair another one or revoke the ones its owner still has. What
 * this machine CAN answer is the half about itself -- whether it still holds a
 * token, how to get a new one, and how to leave.
 *
 * Forgetting is the local half only. The house keeps listing this device until
 * someone revokes it there, and the copy says so rather than implying a
 * reach-back this client does not have.
 */
export function JoinedHouse({ onReconnect }: { onReconnect: () => void }) {
  const s = loadSettings();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState(false);

  const pair = async () => {
    setBusy(true);
    setNote('');
    const name = hasProbe() ? await machineName().catch(() => '') : '';
    const out = await claim(getHttpOrigin(), code, name || 'This Mac');
    setBusy(false);
    if (!out.ok) {
      setNote(out.detail);
      return;
    }
    saveSettings({ deviceToken: out.token });
    setCode('');
    setNote('Paired. Reconnecting.');
    onReconnect();
  };

  const forget = () => {
    /* Back to first run, because that is the truth of the state this leaves
       behind: no house, no token, and a choice to make between installing one
       here and joining another. */
    saveSettings({
      deviceToken: '',
      serverAddress: '',
      remoteHouse: false,
      setupComplete: false,
    });
    window.location.reload();
  };

  return (
    <>
      <Row
        label="This device"
        hint={`Joined the Hearth at ${s.serverAddress || 'nowhere'}. It runs there; nothing is installed on this machine.`}
      >
        <span
          className={`text-[12px] ${s.deviceToken ? 'font-semibold text-[#0F7A52]' : 'text-fawn'}`}
        >
          {s.deviceToken ? 'paired' : 'not paired'}
        </span>
      </Row>

      <Row
        label={s.deviceToken ? 'Pair again' : 'Pair this device'}
        hint="On the machine running the Hearth, open Settings > Connection > Pair a device, and type the six digits it shows."
      >
        <input
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          inputMode="numeric"
          placeholder="000000"
          aria-label="Pairing code"
          className="w-28 rounded-[10px] border border-linen bg-parchment px-3 py-2 text-center font-mono text-[13px] tracking-[0.2em] text-roast placeholder:text-fawn focus:border-fennec focus:bg-fluff focus:outline-none"
        />
        <Btn onClick={pair} disabled={busy || code.length !== 6}>
          {busy ? 'Pairing' : 'Pair'}
        </Btn>
      </Row>

      <Row
        label="Forget this house"
        hint="Clears the address and this device's token here. The house keeps listing this device until someone revokes it there."
      >
        {confirming ? (
          <>
            <Btn onClick={() => setConfirming(false)}>Keep</Btn>
            <Btn tone="warn" onClick={forget}>
              Forget
            </Btn>
          </>
        ) : (
          <Btn tone="warn" onClick={() => setConfirming(true)}>
            Forget
          </Btn>
        )}
      </Row>

      {note && <div className="mt-2 px-1 text-[11.5px] text-fawn">{note}</div>}
    </>
  );
}
