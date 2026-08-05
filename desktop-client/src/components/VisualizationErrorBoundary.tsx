import { Component, type ReactNode } from 'react';
import { useAppStore } from '../store/appStore';

type Props = {
  children: ReactNode;
  fallback: ReactNode;
};

type State = { hasError: boolean; errorInfo: { message: string; assetUrl: string } | null };

/**
 * Catches render errors from @react-three/fiber / drei (e.g. failed GLTF) so the rest of the app keeps running.
 * Captures the failing asset URL and error message, surfaces them in the fallback, and posts the failure
 * to the AgentActivityPanel via pushVisualizationError.
 */
export class VisualizationErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, errorInfo: null };

  static getDerivedStateFromError(err: unknown): State {
    const message = err instanceof Error ? err.message : String(err);
    let assetUrl = '';
    const stack = err instanceof Error ? err.stack || '' : '';
    const urlMatch = stack.match(/\bhttps?:\/\/[^\s\)]+/i);
    if (urlMatch) {
      assetUrl = urlMatch[0];
    } else {
      const msgMatch = message.match(/\bhttps?:\/\/[^\s\)]+/i);
      if (msgMatch) assetUrl = msgMatch[0];
    }
    return { hasError: true, errorInfo: { message, assetUrl } };
  }

  override render() {
    if (this.state.hasError) {
      const info = this.state.errorInfo!;
      // Post the failure to the AgentActivityPanel
      useAppStore.getState().pushVisualizationError({
        assetUrl: info.assetUrl,
        message: info.message,
      });
      return this.props.fallback;
    }
    return this.props.children;
  }
}
