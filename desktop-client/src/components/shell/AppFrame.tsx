import {
  Children,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';

const LEFT_KEY = 'hearth_rail_left_px';
const RIGHT_KEY = 'hearth_rail_right_px';
const LEFT_DEFAULT = 300;
const RIGHT_DEFAULT = 320;
const LEFT_MIN = 220;
const LEFT_MAX = 480;
const RIGHT_MIN = 240;
const RIGHT_MAX = 560;
const CENTER_MIN = 360;

function readStored(key: string, fallback: number): number {
  if (typeof localStorage === 'undefined') return fallback;
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const n = Number(raw);
    return Number.isFinite(n) ? n : fallback;
  } catch {
    return fallback;
  }
}

function writeStored(key: string, value: number) {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(key, String(Math.round(value)));
  } catch {
    // quota / private mode — ignore
  }
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

/* The floating Direction B frame: rounded, shadowed, three-column grid.
   Fills the window (minus the outer hearth-field pad). Left/right rails are
   drag-resizable; widths persist in localStorage. Below lg the stage and rail
   hide (they carry max-lg:hidden themselves) and splitters hide with them. */
export function AppFrame({ children }: { children: ReactNode }) {
  const frameRef = useRef<HTMLDivElement>(null);
  const [leftPx, setLeftPx] = useState(() =>
    clamp(readStored(LEFT_KEY, LEFT_DEFAULT), LEFT_MIN, LEFT_MAX)
  );
  const [rightPx, setRightPx] = useState(() =>
    clamp(readStored(RIGHT_KEY, RIGHT_DEFAULT), RIGHT_MIN, RIGHT_MAX)
  );
  const dragRef = useRef<null | {
    side: 'left' | 'right';
    startX: number;
    startWidth: number;
  }>(null);
  const widthsRef = useRef({ leftPx, rightPx });
  widthsRef.current = { leftPx, rightPx };

  const kids = Children.toArray(children);
  const left = kids[0] ?? null;
  const center = kids[1] ?? null;
  const right = kids[2] ?? null;

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      const drag = dragRef.current;
      const frame = frameRef.current;
      if (!drag || !frame) return;
      const rect = frame.getBoundingClientRect();
      if (drag.side === 'left') {
        const maxForCenter = Math.max(
          LEFT_MIN,
          Math.floor(rect.width - widthsRef.current.rightPx - CENTER_MIN)
        );
        setLeftPx(
          clamp(
            drag.startWidth + (e.clientX - drag.startX),
            LEFT_MIN,
            Math.min(LEFT_MAX, maxForCenter)
          )
        );
      } else {
        const maxForCenter = Math.max(
          RIGHT_MIN,
          Math.floor(rect.width - widthsRef.current.leftPx - CENTER_MIN)
        );
        setRightPx(
          clamp(
            drag.startWidth + (drag.startX - e.clientX),
            RIGHT_MIN,
            Math.min(RIGHT_MAX, maxForCenter)
          )
        );
      }
    };
    const onUp = () => {
      const drag = dragRef.current;
      if (!drag) return;
      dragRef.current = null;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      const w = widthsRef.current;
      if (drag.side === 'left') writeStored(LEFT_KEY, w.leftPx);
      else writeStored(RIGHT_KEY, w.rightPx);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    window.addEventListener('pointercancel', onUp);
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      window.removeEventListener('pointercancel', onUp);
    };
  }, []);

  const startDrag = (side: 'left' | 'right', clientX: number) => {
    dragRef.current = {
      side,
      startX: clientX,
      startWidth: side === 'left' ? leftPx : rightPx,
    };
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  };

  return (
    <div
      ref={frameRef}
      className="relative z-[1] grid h-full min-h-0 w-full min-w-0 flex-1 overflow-hidden rounded-[26px] bg-fluff shadow-frame max-lg:grid-cols-1"
      style={{
        gridTemplateColumns: `${leftPx}px minmax(0,1fr) ${rightPx}px`,
      }}
    >
      {left}
      {center}
      {right}

      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize left rail"
        title="Drag to resize"
        onPointerDown={(e) => {
          e.preventDefault();
          startDrag('left', e.clientX);
        }}
        className="absolute top-0 z-20 hidden h-full w-1.5 -translate-x-1/2 cursor-col-resize touch-none bg-transparent transition-colors hover:bg-ember/25 active:bg-ember/40 max-lg:hidden lg:block"
        style={{ left: leftPx }}
      />
      <div
        role="separator"
        aria-orientation="vertical"
        aria-label="Resize right rail"
        title="Drag to resize"
        onPointerDown={(e) => {
          e.preventDefault();
          startDrag('right', e.clientX);
        }}
        className="absolute top-0 z-20 hidden h-full w-1.5 translate-x-1/2 cursor-col-resize touch-none bg-transparent transition-colors hover:bg-ember/25 active:bg-ember/40 max-lg:hidden lg:block"
        style={{ right: rightPx }}
      />
    </div>
  );
}
