import { render } from 'preact';
import './ui/m3/m3.css';
import './ui/app.css';
import { captureInstallPrompt } from './pwa/install';
import { App } from './app/App';

// Captured before anything else runs: the browser fires it once, early.
captureInstallPrompt();

render(<App />, document.getElementById('app')!);
