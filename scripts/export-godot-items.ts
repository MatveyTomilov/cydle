import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { ITEM_TEMPLATES } from '../src/data/items';
import { UNIQUE_TEMPLATE_BY_ID } from '../src/data/uniques';

const templates = [...ITEM_TEMPLATES, ...Object.values(UNIQUE_TEMPLATE_BY_ID)]
  .sort((left, right) => left.id.localeCompare(right.id));
const ids = new Set(templates.map((template) => template.id));
if (ids.size !== templates.length) throw new Error('Duplicate item template ID in export.');

const output = resolve('game/data/catalog/item_templates.json');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify({ schemaVersion: 1, templates }, null, 2)}\n`, 'utf8');
console.log(`Exported ${templates.length} item templates to ${output}`);
