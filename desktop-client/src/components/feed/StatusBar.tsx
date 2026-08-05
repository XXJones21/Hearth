import { useAppStore } from '../../store/appStore';

/* The house status strip above the composer: who is doing what, right now.
   Persona state and live tool activity, in one quiet line.
   Renders nothing when the house is idle. */

const TOOL_STATUS: [RegExp, string][] = [
  [/^consult_memory/, 'Consulting Selene in the library'],
  [/^(recall|remember)/, 'Leafing through memory'],
  [/^forge_card/, 'Commissioning the workshop'],
  [/^list_cards/, 'Checking the workshop inventory'],
  [/^generate_image/, 'Setting up the easel'],
  [/^check_image/, 'Checking the easel'],
  [/^get_weather/, 'Checking the weather'],
  [/^(web_search|news_headlines)/, 'Looking that up'],
  [/^(set_timer|list_timers|cancel_timer)/, 'Minding the timers'],
  [/^uefn_/, 'Working in the editor'],
];

function toolLabel(names: string[]): string | null {
  for (const name of names) {
    for (const [rx, label] of TOOL_STATUS) {
      if (rx.test(name)) return label;
    }
  }
  return names.length > 0 ? `Working: ${names[0]}` : null;
}

export function StatusBar() {
  const visualState = useAppStore((s) => s.visualState);
  const activeTools = useAppStore((s) => s.activeTools);
  const persona = useAppStore((s) => s.currentPersonaName) ?? 'Sulivan';
  const waiting = useAppStore((s) => s.isWaitingForResponse);

  const items: { text: string; tone: 'active' | 'calm' }[] = [];

  const tool = toolLabel(activeTools);
  if (tool) {
    items.push({ text: `${tool}...`, tone: 'active' });
  } else if (visualState === 'thinking' || waiting) {
    items.push({ text: `${persona} is thinking...`, tone: 'active' });
  } else if (visualState === 'speaking') {
    items.push({ text: `${persona} is speaking`, tone: 'active' });
  } else if (visualState === 'listening') {
    items.push({ text: 'Listening', tone: 'active' });
  }

  if (items.length === 0) return null;

  return (
    <div
      className="mb-2 flex items-center gap-4 px-1 text-[11.5px] text-fawn"
      aria-live="polite"
    >
      {items.map((it) => (
        <span key={it.text} className="flex items-center gap-1.5">
          <span
            className={`h-1.5 w-1.5 rounded-full ${
              it.tone === 'active' ? 'animate-pulse bg-fennec' : 'bg-linen'
            }`}
          />
          {it.text}
        </span>
      ))}
    </div>
  );
}
