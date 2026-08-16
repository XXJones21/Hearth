import { useEffect, useState } from 'react';
import { claim, reachHouse } from '../../lib/pairingApi';
import { deviceName as machineName, hasProbe } from '../../lib/probe';
import { parseAddress } from '../../lib/settings';

/* Joining a house that already runs somewhere else.
 *
 * The other half of first run. "Get started" installs a house on this machine;
 * this screen says there already is one, on the desktop in the other room, and
 * this Mac would like in. Nothing is downloaded and nothing is supervised: the
 * client becomes a window onto a backend it does not own.
 *
 * Two questions, in this order, because they fail differently and the fix for
 * one is not the fix for the other:
 *
 *   where is it   -> /health, which the gateway leaves open precisely so that
 *                    "is my address right" can be answered before "am I
 *                    allowed in"
 *   let me in     -> /pair, a six-digit code the other machine is showing on
 *                    its own screen, traded for this device's token
 *
 * Nothing is saved until the house has agreed. An address written on the way
 * past would leave this client dialling a machine that never let it in, which
 * is indistinguishable, from the inside, from a house that is merely down. */
export function Connect({
  onPaired,
  onBack,
}: {
  onPaired: (address: string, token: string, deviceName: string) => void;
  onBack: () => void;
}) {
  const [address, setAddress] = useState('');
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const [checking, setChecking] = useState(false);
  const [pairing, setPairing] = useState(false);
  /* Reached is a separate state from paired, not a nicety: it is what lets the
     code field appear only once the address is known good, so a rejected code
     means the code and never the address. */
  const [reached, setReached] = useState<string | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!hasProbe()) return;
    machineName()
      .then((n) => n && setName(n))
      .catch(() => {
        /* the field is editable; an empty default is not a failure */
      });
  }, []);

  const parsed = parseAddress(address);

  const check = async () => {
    if (!parsed) return;
    setChecking(true);
    setError('');
    setReached(null);
    const out = await reachHouse(parsed.http);
    setChecking(false);
    if (!out.ok) {
      setError(out.detail);
      return;
    }
    setReached(parsed.http);
  };

  const pair = async () => {
    if (!parsed) return;
    setPairing(true);
    setError('');
    const out = await claim(parsed.http, code, name);
    setPairing(false);
    if (!out.ok) {
      setError(out.detail);
      return;
    }
    onPaired(address.trim(), out.token, name.trim());
  };

  return (
    <>
      <div className="mt-6 flex flex-col items-center">
        <h1 className="text-[26px] font-bold tracking-tight">Join the Hearth you have.</h1>
        <p className="mx-auto mt-3 max-w-[58ch] text-[15px] leading-relaxed text-fawn">
          The machine running it keeps the models, the memory and the voice. This one becomes a
          window onto it, and downloads nothing.
        </p>
      </div>

      <div className="mt-7 w-full max-w-[520px] text-left">
        <label className="block">
          <span className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
            Where it runs
          </span>
          <div className="mt-2 flex gap-2">
            <input
              value={address}
              onChange={(e) => {
                setAddress(e.target.value);
                setReached(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && parsed && !checking) void check();
              }}
              placeholder="192.168.1.20 or the machine's name"
              spellCheck={false}
              aria-label="House address"
              className="w-full flex-1 rounded-full border border-linen bg-parchment px-4 py-2.5 text-[14px] outline-none"
            />
            <button
              onClick={check}
              disabled={!parsed || checking}
              className="rounded-full border border-linen bg-parchment px-4 py-2.5 text-[13.5px] font-semibold text-fawn disabled:opacity-50"
            >
              {checking ? 'Looking' : 'Find it'}
            </button>
          </div>
          <span className="mt-1.5 block text-[12.5px] text-fawn">
            The hostname or IP of the machine Hearth is installed on. Port 18700 unless you say
            otherwise. A tailnet name works from anywhere.
          </span>
        </label>

        {reached && (
          <>
            <p className="mt-5 rounded-xl border border-bubble-line bg-glowtint px-4 py-3 text-[13.5px] leading-snug">
              A Hearth is answering there. On that machine, open Settings and, under Connection,
              add a device. It will show a six-digit code for a few minutes.
            </p>

            <label className="mt-5 block">
              <span className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
                The code it is showing
              </span>
              <div className="mt-2 flex gap-2">
                <input
                  value={code}
                  onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && code.length === 6 && !pairing) void pair();
                  }}
                  inputMode="numeric"
                  placeholder="000000"
                  aria-label="Pairing code"
                  className="w-40 rounded-full border border-linen bg-parchment px-4 py-2.5 text-center font-mono text-[18px] tracking-[0.3em] outline-none"
                />
                <button
                  onClick={pair}
                  disabled={code.length !== 6 || pairing}
                  className="rounded-full bg-roast px-6 py-2.5 text-[14px] font-bold text-cream disabled:opacity-50"
                >
                  {pairing ? 'Pairing' : 'Pair this Mac'}
                </button>
              </div>
            </label>

            <label className="mt-5 block">
              <span className="text-[11.5px] font-semibold uppercase tracking-wide text-fawn">
                What to call this Mac
              </span>
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="This Mac"
                aria-label="Device name"
                className="mt-2 w-full rounded-full border border-linen bg-parchment px-4 py-2.5 text-[14px] outline-none"
              />
              <span className="mt-1.5 block text-[12.5px] text-fawn">
                This is the name in the house's device list, which exists to answer one question:
                which of these to revoke.
              </span>
            </label>
          </>
        )}

        {error && (
          <div className="mt-5 rounded-xl border border-bubble-line bg-bubble px-4 py-3 text-[13.5px] leading-snug">
            {error}
          </div>
        )}

        <div className="mt-7 pb-4">
          <button onClick={onBack} className="text-[13.5px] font-semibold text-fawn underline">
            Install one here instead
          </button>
        </div>
      </div>
    </>
  );
}
