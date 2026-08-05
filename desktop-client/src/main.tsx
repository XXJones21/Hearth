import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { useAppStore } from './store/appStore';
import './styles/globals.css';

if (import.meta.env.DEV) {
  // Dev-only handle for the Puppeteer render gate (synthetic card injection,
  // state assertions). Never present in production builds.
  (window as unknown as Record<string, unknown>).__hearthStore = useAppStore;
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
