import { createRoot } from 'react-dom/client';
import '@fontsource/ibm-plex-sans/400.css';
import '@fontsource/ibm-plex-sans/500.css';
import '@fontsource/ibm-plex-sans/600.css';
import '@fontsource/ibm-plex-sans-arabic/400.css';
import '@fontsource/ibm-plex-sans-arabic/500.css';
import '@fontsource/ibm-plex-sans-arabic/600.css';
import './styles/app.css';
import App from './App';
import { I18nProvider } from './i18n';
import { SessionProvider } from './lib/session';
import { ToastProvider } from './components/ui';
import { initInstall, registerServiceWorker } from './lib/install';

initInstall();
registerServiceWorker(import.meta.env.PROD);

// Not wrapped in StrictMode: dialogs register a history entry so Android "back" closes them,
// and StrictMode's double effects would immediately pop that entry in development.
createRoot(document.getElementById('root')!).render(
  <I18nProvider>
    <ToastProvider>
      <SessionProvider>
        <App />
      </SessionProvider>
    </ToastProvider>
  </I18nProvider>,
);
