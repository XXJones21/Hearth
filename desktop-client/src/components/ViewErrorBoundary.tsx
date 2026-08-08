import { Component, type ErrorInfo, type ReactNode } from 'react';

type Props = { children: ReactNode; label?: string };
type State = { message: string; stack: string } | { message: null; stack: null };

/**
 * The last line before a blank window.
 *
 * React unmounts the whole tree on an uncaught render error, and with nothing
 * catching it the app becomes an empty rectangle: no message, no recovery, no
 * clue which view did it. That is how a single missing field (`person.tiers`,
 * which the surface has never sent) took down the entire client.
 *
 * This is deliberately not a retry button. The state that produced the error
 * is usually still there, so "try again" mostly throws again; going back to
 * the house is the move that works. The message is shown verbatim because the
 * person reading it is the one who can report it.
 */
export class ViewErrorBoundary extends Component<Props, State> {
  state: State = { message: null, stack: null };

  static getDerivedStateFromError(err: unknown): State {
    return {
      message: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack || '' : '',
    };
  }

  override componentDidCatch(err: unknown, info: ErrorInfo) {
    // The webview console is not captured anywhere, so this is the only
    // record that survives long enough to be read.
    console.error('view crashed:', err, info.componentStack);
  }

  override render() {
    if (this.state.message === null) return this.props.children;
    return (
      <div className="flex h-full w-full flex-col items-center justify-center gap-3 p-8 text-center">
        <div className="text-[15px] font-semibold text-roast">
          {this.props.label ? `${this.props.label} could not be drawn.` : 'This screen could not be drawn.'}
        </div>
        <div className="max-w-[60ch] font-mono text-[12px] leading-relaxed text-fawn">
          {this.state.message}
        </div>
        <button
          onClick={() => this.setState({ message: null, stack: null })}
          className="mt-2 rounded-full border border-linen bg-parchment px-5 py-2 text-[13px] font-semibold text-fawn"
        >
          Dismiss
        </button>
      </div>
    );
  }
}
