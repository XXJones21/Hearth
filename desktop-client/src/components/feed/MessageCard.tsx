import { formatTime } from './timelineModel';

type Props = {
  role: 'user' | 'assistant';
  author: string;
  text: string;
  ts: number;
  streaming?: boolean;
};

export function MessageCard({ role, author, text, ts, streaming }: Props) {
  if (role === 'user') {
    return (
      <div className="max-w-[520px] rounded-2xl rounded-bl-md border border-bubble-line bg-bubble px-4 py-2.5 text-[14px] text-roast shadow-soft">
        <span className="block min-w-0 whitespace-pre-wrap break-words [overflow-wrap:anywhere]">
          {text}
        </span>
      </div>
    );
  }
  return (
    <div
      className={`max-w-[560px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft ${
        streaming ? 'animate-pulse' : ''
      }`}
    >
      <div className="mb-1 flex items-baseline gap-2">
        <h3 className="text-[14px] font-semibold text-roast">{author}</h3>
        <span className="ml-auto whitespace-nowrap text-[11px] text-fawn">
          {streaming ? 'writing...' : formatTime(ts)}
        </span>
      </div>
      <span className="block min-w-0 whitespace-pre-wrap break-words text-[14px] text-roast [overflow-wrap:anywhere]">
        {text}
      </span>
    </div>
  );
}
