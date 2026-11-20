// Revision: AI-authored Brainrot Escape Disaster (final production release) | Place ID 73488091337421 | Play Code makefun-kale-oasis-guppy
//
// main.ts — entrypoint for roblox-brainrot-01 (Brainrot Escape Disaster)
//
// Verifies the built place, source, and play files exist, copies them (plus any
// screenshots) into the make.fun output directory, and writes the dossier the
// bounty scorer reads back.

import { existsSync, mkdirSync, cpSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildDossier } from './vendor/makefun-roblox.ts';

const ROOT = import.meta.dirname;
const OUTPUT_DIR = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

function requireExists(path: string, label: string): void {
  if (!existsSync(path)) {
    throw new Error(`main.ts: ${label} not found at ${path}`);
  }
}

function copyFiltered(src: string, dest: string): void {
  cpSync(src, dest, {
    recursive: true,
    filter: (source: string) => {
      const base = source.split(/[\\/]/).pop() ?? '';
      return !base.startsWith('.');
    },
  });
}

function main(): void {
  const gameRbxl = join(ROOT, 'game.rbxl');
  const playJson = join(ROOT, 'PLAY.json');
  const srcDir = join(ROOT, 'src');

  requireExists(gameRbxl, 'game.rbxl');
  requireExists(playJson, 'PLAY.json');
  requireExists(srcDir, 'src/');

  mkdirSync(OUTPUT_DIR, { recursive: true });

  copyFiltered(gameRbxl, join(OUTPUT_DIR, 'game.rbxl'));
  copyFiltered(playJson, join(OUTPUT_DIR, 'PLAY.json'));
  copyFiltered(srcDir, join(OUTPUT_DIR, 'src'));

  const screenshotsDir = join(ROOT, 'screenshots');
  if (existsSync(screenshotsDir)) {
    copyFiltered(screenshotsDir, join(OUTPUT_DIR, 'screenshots'));
  }

  const dossier = buildDossier(OUTPUT_DIR, {
    text_max_bytes: 65536,
    max_bytes: 262144,
    max_instances: 500000,
  });

  writeFileSync(join(OUTPUT_DIR, 'dossier.json'), dossier);

  console.log(`main.ts: wrote ${dossier.byteLength} bytes to ${join(OUTPUT_DIR, 'dossier.json')}`);
}

main();
