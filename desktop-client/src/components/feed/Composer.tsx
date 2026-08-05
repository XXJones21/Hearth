import { type FormEvent, useState } from 'react';
import { useAppStore } from '../../store/appStore';

type Props = {
  onSend: (text: string) => void;
};

export function Composer({ onSend }: Props) {
  const [draft, setDraft] = useState('');
  const connection = useAppStore((s) => s.connection);
  const isWaiting = useAppStore((s) => s.isWaitingForResponse);
  const setInputFocused = useAppStore((s) => s.setInputFocused);
  const disabled = connection !== 'ready' || isWaiting;

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (disabled || !draft.trim()) return;
    onSend(draft);
    setDraft('');
  };

  return (
    <form onSubmit={submit} className="mt-3 flex gap-2.5">
      <textarea
        aria-label="Message input"
        className="max-h-[140px] min-h-[46px] flex-1 resize-none rounded-3xl border border-linen bg-parchment px-4 py-3 text-sm text-roast outline-none placeholder:text-fawn focus:border-fennec/50"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            submit(e);
          }
        }}
        onFocus={() => setInputFocused(true)}
        onBlur={() => setInputFocused(false)}
        placeholder={
          connection === 'ready'
            ? 'Ask anything, or just start talking'
            : 'Connecting to your home server...'
        }
        disabled={disabled}
      />
      <button
        type="submit"
        className="shrink-0 self-end rounded-full bg-roast px-5 py-3 text-sm font-bold text-cream disabled:opacity-30"
        disabled={disabled || !draft.trim()}
      >
        Send
      </button>
    </form>
  );
}
