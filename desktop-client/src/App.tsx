import { useEffect, useState } from 'react';
import { AppFrame } from './components/shell/AppFrame';
import { SetupFlow } from './components/setup/SetupFlow';
import { Feed } from './components/feed/Feed';
import { LibraryView } from './components/journal/LibraryView';
import { PersonaStage } from './components/stage/PersonaStage';
import { Rail } from './components/rail/Rail';
import { AppsView } from './components/apps/AppsView';
import { PersonasView } from './components/personas/PersonasView';
import { ViewErrorBoundary } from './components/ViewErrorBoundary';
import { SettingsView } from './components/settings/SettingsView';
import { useHearthWebSocket } from './hooks/useHearthWebSocket';
import { ttsPlayer } from './lib/audioPlayer';
import { applyPersonaTheme } from './lib/personaTheme';
import { houseStart } from './lib/house';
import { hasProbe, installRoot, installState } from './lib/probe';
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
  const { sendTextQuery, switchPersona, startNewSession, resumeSession, reconnect, disconnect } =
    useHearthWebSocket(!showSetup);

  /* The settings flag is only a cache. The truth is the install record on
     disk, so boot revalidates: a deleted or gutted install folder routes back
     into setup, which is what makes deleting the folder a real uninstall.
     A validated install starts the house: the supervised backend tree is the
     client's to run now, and the socket that dials 18700 finds something
     because we put it there. */
  useEffect(() => {
    const s = loadSettings();
    if (!s.setupComplete || !hasProbe()) return;
    installState(s.installRoot || undefined)
      .then(async (state) => {
        if (!state.ok) {
          saveSettings({ setupComplete: false });
          setShowSetup(true);
          return;
        }
        const root = s.installRoot || (await installRoot());
        houseStart(root).catch((e) => {
          console.error('house did not start:', e);
        });
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
    /* Browsers only reliably start an AudioContext from a user gesture, and
       the first frame of a reply arrives inside a WebSocket handler, which is
       not one. Take the first click or keypress of the session as permission
       so the first thing he ever says is not the thing that gets swallowed. */
    const unlock = () => ttsPlayer.unlock();
    window.addEventListener('pointerdown', unlock, { once: true });
    window.addEventListener('keydown', unlock, { once: true });
    return () => {
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('keydown', unlock);
    };
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
    <div className="hearth-field flex h-full min-h-0 items-stretch overflow-hidden p-6">
      {showSetup ? (
        /* One centred column. During first run there is no persona to stand on
           a stage and no house to put a rail beside, so the frame is a single
           surface. This matches hearth-setup-flow.html. */
        <div className="relative z-[1] mx-auto flex h-full min-h-0 w-full max-w-[900px] flex-col overflow-hidden rounded-[26px] bg-fluff shadow-frame">
          <SetupFlow
            onExit={(installed) => {
              /* Only a completed install marks setup complete. Closing out of
                 a blocked or unfinished setup must not: the flag is the only
                 thing standing between a fresh install and adopting whatever
                 backend is already listening on this machine. A completed one
                 starts the house on the way in. */
              if (installed) {
                const s = saveSettings({ setupComplete: true });
                if (s.installRoot) {
                  houseStart(s.installRoot).catch((e) => {
                    console.error('house did not start:', e);
                  });
                }
              }
              setShowSetup(false);
            }}
          />
        </div>
      ) : (
      <AppFrame>
        <PersonaStage config={personaConfig} onSwitch={switchPersona} />
        {activeView === 'journal' ? (
          <ViewErrorBoundary label="The journal">
            <LibraryView />
          </ViewErrorBoundary>
        ) : activeView === 'settings' ? (
          <ViewErrorBoundary label="Settings">
            <SettingsView onReconnect={redial} />
          </ViewErrorBoundary>
        ) : activeView === 'personas' ? (
          <ViewErrorBoundary label="Personas">
            <PersonasView />
          </ViewErrorBoundary>
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
        <Rail
          onNewSession={startNewSession}
          onResumeSession={resumeSession}
          sessionBusy={isWaitingForResponse}
        />
      </AppFrame>
      )}
    </div>
  );
}
