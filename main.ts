// Revision: verified 1280x720 primary thumbnail integration and tour data (round 3) | Place ID 73488091337421 | Play Code makefun-kale-oasis-guppy | Timestamp: 2026-11-20 15:23:00 +07:00
// Brainrot Escape Disaster: the roblox-brainrot-01 entry (Node 22, standard library only).
//
// The game is this directory's Rojo project (default.project.json maps src/server to
// ServerScriptService.Server and src/client to StarterPlayer.StarterPlayerScripts.Client), built into
// game.rbxl with `rojo build default.project.json --output game.rbxl`. Players run from the Safe Zone into a
// 3D field of meme brainrots, carry them home in a bag, bank them on their base for cash per second, buy
// speed / capacity / magnet upgrades, rebirth for a multiplier, and outrun the tsunami that sweeps the map.
//
// This program hands the game in: it copies game.rbxl, src/, screenshots/ and PLAY.json from beside this
// file to /output and writes /output/dossier.json, the summary the judge reads, with the vendored make.fun
// library (vendor/makefun-roblox.ts, unchanged).
//
// Every name under /output starts with a letter, a digit or _ and holds only letters, digits, . _ and -: the
// grader fails an entry whose output holds any other, so a file such as .gitkeep or .DS_Store copied in fails it.
// So src/ and screenshots/ are copied without any name that starts with a dot, at any depth.
//
// Outside the grader's container, MAKEFUN_OUTPUT_DIR stands in for /output:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

/** cpSync's filter: leave out every file and directory whose name starts with a dot (.gitkeep, .DS_Store, .git). */
const notDotted = (path: string): boolean => !basename(path).startsWith('.');

// Fail early with a clear message rather than a bare ENOENT if the place has not been built yet.
for (const required of ['game.rbxl', 'PLAY.json', 'src']) {
  if (!existsSync(join(here, required))) {
    throw new Error(`missing ${required}: run \`rojo build default.project.json --output game.rbxl\` first`);
  }
}

mkdirSync(out, { recursive: true });
copyFileSync(join(here, 'game.rbxl'), join(out, 'game.rbxl'));
copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));
cpSync(join(here, 'src'), join(out, 'src'), { recursive: true, filter: notDotted });
mkdirSync(join(out, 'screenshots'), { recursive: true });
if (existsSync(join(here, 'screenshots'))) cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true, filter: notDotted });

// The scorer's own caps (reference/gate.json): only text_max_bytes shapes the bytes; the others refuse an entry the
// scorer would refuse (more than 4 screenshots or one over 256 KiB; a place of more than 500000 instances, whose
// scripts' sources come to over 8 MiB or whose scripts' paths come to over 1048576 characters, in all).
writeFileSync(
  join(out, 'dossier.json'),
  buildDossier(out, { text_max_bytes: 65536, screenshots: { max: 4, max_bytes: 262144 }, max_instances: 500000, scripts_max_source_bytes: 8388608, scripts_max_path_chars: 1048576 }),
);
