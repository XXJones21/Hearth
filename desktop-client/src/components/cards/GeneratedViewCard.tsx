import type { CardProps, GeneratedViewProps, GeneratedViewSection } from './types';
import { resolvePersonaAssetUrl } from '../../lib/resolveAssetUrl';

const MAX_SECTIONS = 12;

function Section({ section, hero }: { section: GeneratedViewSection; hero: boolean }) {
  switch (section.kind) {
    case 'text':
      return <p className="text-[14px] text-roast">{section.body}</p>;
    case 'stat':
      return (
        <div>
          <div className={`font-bold text-roast ${hero ? 'text-[28px]' : 'text-[21px]'}`}>
            {section.value}
          </div>
          <div className="text-[11.5px] text-fawn">{section.label}</div>
        </div>
      );
    case 'stat_row':
      return (
        <div className="flex flex-wrap gap-5">
          {(section.stats || []).slice(0, 4).map((s, i) => (
            <div key={i}>
              <div className="text-[21px] font-bold text-roast">{s.value}</div>
              <div className="text-[11.5px] text-fawn">{s.label}</div>
            </div>
          ))}
        </div>
      );
    case 'image':
      return (
        <img
          src={resolvePersonaAssetUrl(section.src, '')}
          alt=""
          className="max-h-56 w-full rounded-xl object-cover"
        />
      );
    case 'divider':
      return <hr className="border-linen" />;
    default:
      return null;
  }
}

export function GeneratedViewCard({ props }: CardProps) {
  const gv = props as GeneratedViewProps;
  const sections = Array.isArray(gv.sections) ? gv.sections.slice(0, MAX_SECTIONS) : [];
  const template = gv.template || 'plain';
  const isComparison = template === 'comparison';

  return (
    <div className="max-w-[560px] rounded-2xl border border-linen bg-fluff px-4 py-3 shadow-soft">
      {gv.title && (
        <div className="mb-2 text-[11.5px] font-bold uppercase tracking-wider text-ember">
          {gv.title}
        </div>
      )}
      <div className={isComparison ? 'grid grid-cols-2 gap-x-5 gap-y-3' : 'flex flex-col gap-3'}>
        {sections.map((section, i) => (
          <Section key={i} section={section} hero={template === 'hero_stat' && i === 0} />
        ))}
      </div>
    </div>
  );
}
