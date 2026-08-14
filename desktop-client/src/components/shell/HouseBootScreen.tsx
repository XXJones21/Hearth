type Props = {
  detail: string;
  error?: string;
  onRetry?: () => void;
  onOpenSettings?: () => void;
};

/* Full-window waking overlay. The house start used to run as a sync Tauri
   command on the UI thread, so this chrome painted once and then Windows
   marked the window Not Responding while llama-server loaded. The command is
   async now and this overlay stays on a live main thread, which is the whole
   reason it can animate and say what it is waiting for. */
export function HouseBootScreen({ detail, error, onRetry, onOpenSettings }: Props) {
  const failed = Boolean(error);

  return (
    <div
      className="absolute inset-0 z-50 flex items-center justify-center bg-cream/92 p-8"
      role="status"
      aria-live="polite"
      aria-busy={!failed}
    >
      <div className="max-w-md text-center">
        <div
          className={`mx-auto mb-6 h-16 w-16 rounded-full border-2 border-ember bg-glowtint ${
            failed ? '' : 'breathe'
          }`}
          aria-hidden="true"
        />
        <p className="text-[11px] font-bold uppercase tracking-[0.18em] text-ember">
          {failed ? 'House did not wake' : 'Waking the house'}
        </p>
        <p className="mt-3 text-[16px] leading-relaxed text-roast">
          {failed ? error : detail || 'Starting the house. The model can take a minute.'}
        </p>
        {!failed && (
          <p className="mt-2 text-[13px] italic text-fawn">
            You can leave this window in front. It stays responsive while the
            backend comes up.
          </p>
        )}
        {failed && (
          <div className="mt-6 flex justify-center gap-2">
            {onRetry && (
              <button
                type="button"
                onClick={onRetry}
                className="rounded-full border border-linen bg-fluff px-4 py-2 text-[13px] font-semibold text-roast shadow-soft hover:border-bubble-line"
              >
                Try again
              </button>
            )}
            {onOpenSettings && (
              <button
                type="button"
                onClick={onOpenSettings}
                className="rounded-full border border-linen bg-fluff px-4 py-2 text-[13px] font-semibold text-fawn shadow-soft hover:border-bubble-line"
              >
                Settings
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
