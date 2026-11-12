import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { CONTRACT_TEMPLATES, QUESTS } from '../src/data/quests';

const output = resolve('game/data/catalog/quest_definitions.json');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify({ schemaVersion: 1, quests: QUESTS, contracts: CONTRACT_TEMPLATES }, null, 2)}\n`, 'utf8');
console.log(`Exported ${QUESTS.length} quests and ${CONTRACT_TEMPLATES.length} contracts to ${output}`);
