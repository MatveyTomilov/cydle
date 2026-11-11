import { validateCatalog } from '../src/data/validate';

const issues = validateCatalog();
if (issues.length) {
  console.error(`CYDLE data validation failed (${issues.length} issue${issues.length === 1 ? '' : 's'}):`);
  for (const issue of issues) console.error(`- ${issue}`);
  process.exitCode = 1;
} else {
  console.log('CYDLE content catalogs: identity, campaign, biome, item, enemy, quest, and starter references are valid.');
}
