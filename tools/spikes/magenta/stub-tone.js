// Magenta.js imports Tone.js (audio playback) at load time; its ESM build does not
// resolve under Node 24 require(). We never play audio, so serve an empty module.
const Module = require('module');
const orig = Module._resolveFilename;
Module._resolveFilename = function (req, ...rest) {
  if (req === 'tone') return require.resolve('./tone-empty.js');
  return orig.call(this, req, ...rest);
};
