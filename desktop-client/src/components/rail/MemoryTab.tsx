import { useEffect, useState } from 'react';
import { fetchFacts } from '../../lib/journal';

/* What your persona has come to know about you.
   Live, from the second brain's operator facts. Until 2026-08-05 this was two
   invented sentences carrying fabricated attribution ("you said this, June 12"),
   which is a worse thing to show a person than nothing at all. */
export function MemoryTab() {
  const [facts, setFacts] = useState<string[] | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    fetchFacts()
      .then((body) => {
        if (!live) return;
        // The facts file is markdown. Bullets are the facts; headings are not.
        setFacts(
          body
            .split('\n')
            .map((l) => l.trim())
            .filter((l) => l.startsWith('- ') || l.startsWith('* '))
            .map((l) => l.slice(2).trim())
            .filter(Boolean),
        );
      })
      .catch(() => {
        if (live) setFailed(true);
      });
    return () => {
      live = false;
    };
  }, []);

  if (failed) return <Shell>Your second brain is not reachable right now.</Shell>;
  if (facts === null) return <Shell>Reading.</Shell>;
  if (facts.length === 0) {
    return (
      <Shell>
        Nothing remembered yet. Facts appear here as your persona learns them from
        talking to you.
      </Shell>
    );
  }

  return (
    <Shell>
      <div className="flex flex-col gap-2">
        {facts.map((f) => (
          <div
            key={f}
            className="rounded-xl bg-parchment px-3 py-2 text-[12.5px] leading-snug text-roast"
          >
            {f}
          </div>
        ))}
      </div>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-4">
      <h3 className="mb-2 text-[11px] font-bold uppercase tracking-wider text-fawn">
        Remembered about you
      </h3>
      {typeof children === 'string' ? (
        <p className="text-[12.5px] leading-snug text-fawn">{children}</p>
      ) : (
        children
      )}
    </div>
  );
}
