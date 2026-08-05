/* Conversations you can pick back up.
 *
 * Deliberately an empty state rather than a fabricated list. The data exists:
 * every conversation is written to an .scx file carrying its full history. What
 * does not exist yet is a server endpoint to list them or a protocol action to
 * rehydrate one. Both are tracked as their own task.
 *
 * Shipping a plausible-looking list of sessions that cannot actually be opened
 * would be the same mistake the old Memory tab made. */
export function SessionsTab() {
  return (
    <div className="mt-4">
      <h3 className="mb-2 text-[11px] font-bold uppercase tracking-wider text-fawn">
        Earlier conversations
      </h3>
      <p className="text-[12.5px] leading-snug text-fawn">
        Not yet. Your conversations are being kept, and picking one back up is the
        next thing being built here.
      </p>
      <p className="mt-2 text-[12.5px] leading-snug text-fawn">
        In the meantime, the Journal holds what your personas wrote down about
        them.
      </p>
    </div>
  );
}
