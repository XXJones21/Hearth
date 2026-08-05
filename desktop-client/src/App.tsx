import { useEffect, useState } from 'react';
import { AppFrame } from './components/shell/AppFrame';
import { SetupFlow } from './components/setup/SetupFlow';
import { Feed } from './components/feed/Feed';
import { LibraryView } from './components/journal/LibraryView';
import { PersonaStage } from './components/stage/PersonaStage';
import { Rail } from './components/rail/Rail';
import { AppsView } from './components/apps/AppsView';
import { PersonasView } from './components/personas/PersonasView';
import { SettingsView } from './components/settings/SettingsView';
import { useHearthWebSocket } from './hooks/useHearthWebSocket';
import { ttsPlayer } from './lib/audioPlayer';
import { applyPersonaTheme } from './lib/personaTheme';
import { applyDocumentSettings, loadSettings, saveSettings } from './lib/settings';
import { useAppStore } from './store/appStore';

export default function App() {
  const personaConfig = useAppStore((s) => s.personaConfig);
  const connection = useAppStore((s) => s.connection);
  const isWaitingForResponse = useAppStore((s) => s.isWaitingForResponse);
  const activeView = useAppStore((s) => s.activeView);
  const { sendTextQuery, switchPersona, reconnect, disconnect } = useHearthWebSocket();

  /* First-run setup. Not yet on the normal path: a fresh install will land
     here by itself once provisioning exists. Until then it opens on
     Ctrl+Shift+S, or with #setup in the address, so it can be exercised on a
     machine that is already set up. */
  /* A fresh install opens into setup, not into the house. Until setup has been
     completed once, there is no backend to talk to and nothing to show. */
  const [showSetup, setShowSetup] = useState(
    !loadSettings().setupComplete ||
      (typeof window !== 'undefined' && window.location.hash === '#setup'),
  );
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 's') {
        e.preventDefault();
        setShowSetup((v) => !v);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    const s = loadSettings();
    applyDocumentSettings(s);
    ttsPlayer.setOutput(s.voiceEnabled, s.voiceVolume);
  }, []);

  /* Settings > Connection edits the address; the socket only reads it when it
     dials, so applying means dropping the current one first. */
  const redial = () => {
    disconnect();
    window.setTimeout(reconnect, 120);
  };

  useEffect(() => {
    const root = document.getElementById('root');
    if (!root) return;
    applyPersonaTheme(root, personaConfig);
  }, [personaConfig]);

  const send = (text: string) => {
    if (connection === 'ready' && !isWaitingForResponse) {
      sendTextQuery(text);
    }
  };

  return (
    <div className="hearth-field flex h-full min-h-screen items-center justify-center overflow-hidden p-6">
      <AppFrame>
        <PersonaStage config={personaConfig} onSwitch={switchPersona} />
        {showSetup ? (
          <SetupFlow
            onExit={() => {
              saveSettings({ setupComplete: true });
              setShowSetup(false);
            }}
          />
        ) : activeView === 'journal' ? (
          <LibraryView />
        ) : activeView === 'settings' ? (
          <SettingsView onReconnect={redial} />
        ) : activeView === 'personas' ? (
          <PersonasView />
        ) : activeView === 'apps' ? (
          <AppsView
            onAsk={(text) => {
              useAppStore.getState().setActiveView('home');
              send(text);
            }}
          />
        ) : (
          <Feed onSend={send} />
        )}
        <Rail />
      </AppFrame>
    </div>
  );
}
