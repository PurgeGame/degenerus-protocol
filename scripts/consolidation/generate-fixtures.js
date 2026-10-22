import fs from 'node:fs';
import { DEPLOYMENTS, aliasOwners } from '../lib/deploymentManifest.js';
aliasOwners();
const check = process.argv.includes('--check');
const start = '        // BEGIN CANONICAL DEPLOYMENTS';
const end = '        // END CANONICAL DEPLOYMENTS';
for (const [file, bounded, affiliate] of [
  ['test/fuzz/helpers/DeployProtocol.sol', false, '_affiliateBootstrap()'],
  ['test/helpers/BoundedDeployProtocol.sol', true, '_affiliateBootstrap()'],
  ['test/fork/ForkDeployProtocol.sol', false, '(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0))'],
]) {
  let text = fs.readFileSync(file, 'utf8');
  const lines = [start, '        (address[] memory owners, bytes32[] memory codes, uint8[] memory kicks,',
    `            address[] memory players, bytes32[] memory refs) = ${affiliate};`];
  for (const row of DEPLOYMENTS) {
    const args = row.key === 'ICONS_32' ? 'false' : row.key === 'AFFILIATE' ? 'owners, codes, kicks, players, refs' : '';
    const fromArtifact = bounded || ['DegenerusGamePassModule', 'DegenerusGameEndgameModule'].includes(row.fixtureType);
    const creation = fromArtifact ? `${row.fixtureType}(payable(deployCode("${row.fixtureType}.sol:${row.fixtureType}", abi.encode(${args}))))` : `new ${row.fixtureType}(${args})`;
    lines.push(`        ${row.fixtureField} = ${creation};`);
  }
  // An alias can have a distinct interface type; no CREATE is emitted for it.
  for (const row of DEPLOYMENTS) for (const [alias, binding] of Object.entries(row.fixtureAliases || {})) {
    if (!row.aliases.includes(alias)) throw new Error(`Undeclared fixture alias: ${alias}`);
    lines.push(`        ${binding.field} = ${binding.type}(payable(address(${row.fixtureField})));`);
  }
  lines.push(end);
  const begin = text.indexOf(start), finish = text.indexOf(end);
  if (begin < 0 || finish < 0) throw new Error(`Missing generation markers: ${file}`);
  const generated = text.slice(0, begin) + lines.join('\n') + text.slice(finish + end.length);
  if (check && generated !== text) throw new Error(`Stale canonical fixture: ${file}`);
  if (!check) fs.writeFileSync(file, generated);
}
