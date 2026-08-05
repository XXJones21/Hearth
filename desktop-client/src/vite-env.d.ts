/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_HEARTH_WS: string;
  readonly VITE_HEARTH_HTTP_ORIGIN: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
