/* Bundled at document end in the configured HTTPS main frame only. No token bridge. */
(() => {
  'use strict';
  window.MiniBridgeAppLifecycle = Object.freeze({
    pause() {
      const result = {cameraStopped: false, audioStopped: false};
      if (typeof stopCamera === 'function' &&
          ((typeof cameraActive !== 'undefined' && cameraActive) ||
           (typeof cameraStartPending !== 'undefined' && cameraStartPending))) {
        try { stopCamera('page_hidden'); result.cameraStopped = true; } catch {}
      }
      if (typeof ctx !== 'undefined' && ctx && ctx.state !== 'closed' && typeof stopListening === 'function') {
        try { stopListening(); result.audioStopped = true; } catch {}
      }
      if (typeof lockVault === 'function') { try { lockVault(); } catch {} }
      return result;
    },
    resume() {
      const page = typeof document !== 'undefined' && document.querySelector('[data-view="camera"]');
      if (!page || page.hidden || typeof hasMediaDevice !== 'function' || !hasMediaDevice() ||
          typeof reconnectCamera !== 'function' ||
          (typeof cameraActive !== 'undefined' && cameraActive) ||
          (typeof cameraStartPending !== 'undefined' && cameraStartPending)) return false;
      if (typeof cameraWs === 'undefined' || !cameraWs || cameraWs.readyState === 2 || cameraWs.readyState === 3) {
        reconnectCamera();
        return true;
      }
      return false;
    }
  });
})();
