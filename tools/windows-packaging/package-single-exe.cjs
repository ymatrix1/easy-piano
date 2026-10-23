const fs = require('node:fs');
const path = require('node:path');
const generateEvb = require('generate-evb');

const [bundleArgument, outputArgument] = process.argv.slice(2);
if (!bundleArgument || !outputArgument) {
  throw new Error('Usage: node package-single-exe.cjs <flutter-release-dir> <output-exe>');
}

const bundle = path.resolve(bundleArgument);
const outputExe = path.resolve(outputArgument);
const launcher = path.join(bundle, 'easy_piano.exe');
const bridge = path.join(bundle, 'easy_piano_bridge.dll');
const manifest = path.join(bundle, 'data', 'flutter_assets', 'AssetManifest.bin');

for (const required of [launcher, bridge, manifest]) {
  if (!fs.existsSync(required)) {
    throw new Error(`Windows release bundle is missing required file: ${required}`);
  }
}
if (outputExe.startsWith(`${bundle}${path.sep}`)) {
  throw new Error('The packed executable must be written outside the Flutter bundle.');
}

const projectFile = path.join(path.dirname(outputExe), 'easy-piano-portable.evb');
generateEvb(projectFile, launcher, outputExe, bundle, {
  filter: (filePath, _name, isDirectory) =>
    isDirectory || path.resolve(filePath).toLowerCase() !== launcher.toLowerCase(),
  evbOptions: {
    deleteExtractedOnExit: true,
    compressFiles: true,
    shareVirtualSystem: false,
    mapExecutableWithTemporaryFile: true,
    allowRunningOfVirtualExeFiles: true,
  },
});

console.log(`Generated Enigma project: ${projectFile}`);
