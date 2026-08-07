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
import { hasProbe, installState } from './lib/probe';
import { applyDocumentSettings, loadSettings, saveSettings } from './lib/settings';
import { useAppStore } from './store/appStore';

export default function App() {
  const personaConfig = useAppStore((s) => s.personaConfig);
  const connection = useAppStore((s) => s.connection);
  const isWaitingForResponse = useAppStore((s) => s.isWaitingForResponse);
  const activeView = useAppStore((s) => s.activeView);
  /* A fresh install opens into setup, not into the house. Until setup has been
     completed once there is no backend, so the socket must not dial either:
     a client that connects before setup adopts whatever is already running on
     the machine and presents it as the user's own. */
  const [showSetup, setShowSetup] = useState(
    !loadSettings().setupComplete ||
      (typeof window !== 'undefined' && window.location.hash === '#setup'),
  );
  const { sendTextQuery, switchPersona, reconnect, disconnect } =
    useHearthWebSocket(!showSetup);

  /* The settings flag is only a cache. The truth is the install record on
     disk, so boot revalidates: a deleted or gutted install folder routes back
     into setup, which is what makes deleting the folder a real uninstall. */
  useEffect(() => {
    const s = loadSettings();
    if (!s.setupComplete || !hasProbe()) return;
    installState(s.installRoot || undefined)
      .then((state) => {
        if (!state.ok) {
          saveSettings({ setupComplete: false });
          setShowSetup(true);
        }
      })
      .catch(() => {
        /* the probe failing is not evidence the install is gone */
      });
  }, []);
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
      {showSetup ? (
        /* One centred column. During first run there is no persona to stand on
           a stage and no house to put a rail beside, so the frame is a single
           surface. This matches hearth-setup-flow.html. */
        <div className="relative z-[1] flex h-full max-h-[min(860px,calc(100vh_-_3rem))] w-full max-w-[900px] flex-col overflow-hidden rounded-[26px] bg-fluff shadow-frame">
          <SetupFlow
            onExit={(installed) => {
              /* Only a completed install marks setup complete. Closing out of
                 a blocked or unfinished setup must not: the flag is the only
                 thing standing between a fresh install and adopting whatever
                 backend is already listening on this machine. */
              if (installed) saveSettings({ setupComplete: true });
              setShowSetup(false);
            }}
          />
        </div>
      ) : (
      <AppFrame>
        <PersonaStage config={personaConfig} onSwitch={switchPersona} />
        {activeView === 'journal' ? (
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
      )}
    </div>
  );
}
