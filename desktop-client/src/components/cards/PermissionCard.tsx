import { useState } from 'react';
import { getHttpOrigin } from '../../lib/config';
import type { CardProps, PermissionCardProps } from './types';

/* The one card the operator must answer before the turn can finish. A folder
   outside the house's allow-list does not fail and is not silently opened:
   the tool parks, this card asks, and the same call resumes on Approve. The
   house stays quiet the whole time it is on screen, so the buttons are the
   only thing waiting to be answered. */
export function PermissionCard({ props }: CardProps) {
  const p = props as unknown as PermissionCardProps;
  const [status, setStatus] = useState(p.status || 'pending');
  const [deciding, setDeciding] = useState<'approve' | 'deny' | null>(null);
  const [error, setError] = useState('');

  const decide = async (approve: boolean) => {
    if (!p.request_id || status !== 'pending') return;
    setDeciding(approve ? 'approve' : 'deny');
    setError('');
    try {
      const res = await fetch(`${getHttpOrigin()}/files/decide`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ request_id: p.request_id, approve }),
      });
      const data = (await res.json()) as { ok?: boolean; status?: string; error?: string };
      if (!data.ok) {
        setError(data.error || 'That did not go through.');
        return;
      }
      setStatus(data.status || (approve ? 'granted' : 'denied'));
    } catch {
      setError('Could not reach the house.');
    } finally {
      setDeciding(null);
    }
  };

  const action = p.action || 'read';
  const pending = status === 'pending';
  /* A create request is a different question. "Allow access to D:\Recipes for
     create" reads as consent to open something that is not there; what is
     actually being asked is whether to make it. */
  const creating = action === 'create';

  return (
    <div className="max-w-[520px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      <div className="text-[11.5px] font-bold uppercase tracking-wider text-ember">
        {creating ? 'New folder' : 'Folder access'}
      </div>
      <p className="mt-1.5 text-[14px] leading-relaxed text-roast">
        {creating ? (
          <>
            Create <span className="font-medium">{p.path || 'this folder'}</span> and
            let Hearth write there?
          </>
        ) : (
          <>
            Allow access to <span className="font-medium">{p.path || 'this folder'}</span>
            {action ? ` for ${action}` : ''}?
          </>
        )}
      </p>
      <p className="mt-1 text-[12px] text-fawn">
        This grant stays on this house until you remove it from file_grants.yaml.
      </p>
      {pending ? (
        <div className="mt-3 flex items-center gap-2">
          <button
            type="button"
            disabled={deciding !== null}
            onClick={() => void decide(true)}
            className="rounded-full border border-ember bg-gradient-to-b from-honey to-fennec px-3.5 py-[6px] text-[12px] font-semibold text-roast shadow-soft disabled:opacity-50"
          >
            {deciding === 'approve' ? 'Approving' : 'Approve'}
          </button>
          <button
            type="button"
            disabled={deciding !== null}
            onClick={() => void decide(false)}
            className="rounded-full border border-linen bg-fluff px-3.5 py-[6px] text-[12px] font-semibold text-fawn shadow-soft disabled:opacity-50"
          >
            Deny
          </button>
        </div>
      ) : (
        <p className="mt-3 text-[13px] text-roast">
          {status === 'granted' ? 'Granted. Continuing.' : 'Denied.'}
        </p>
      )}
      {error && <p className="mt-2 text-[12px] text-[#8A3D2A]">{error}</p>}
    </div>
  );
}
