// Cold, separately committed transactions comparing legacy and final production helpers.
// Run against a disposable local Anvil, never a public RPC.
const fs = require('node:fs');
const path = require('node:path');
const { ethers } = require('ethers');

async function main() {
  const artifactRoot = process.argv[2];
  if (!artifactRoot) throw new Error('Pass the isolated forge-out directory');
  const provider = new ethers.JsonRpcProvider('http://127.0.0.1:18572');
  provider.pollingInterval = 10;
  const signer = await provider.getSigner(0);
  const player = '0x00000000000000000000000000000000000A11cE';
  const deploy = async (name) => {
    const artifact = JSON.parse(fs.readFileSync(path.join(artifactRoot, 'StableEntryOwnerMeasurement.t.sol', `${name}.json`)));
    const contract = await new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, signer).deploy();
    await contract.waitForDeployment();
    return contract;
  };
  const old = await deploy('CurrentEntryOwnerMeasurement');
  const candidate = await deploy('StableEntryOwnerMeasurement');
  const cost = async (contract, action, level) => Number((await (await contract[action](player, level)).wait()).gasUsed);
  const result = { scope: 'Queue/owner storage kernel; separate transactions, receipt gas after refunds; excludes payment and trait-generation work', first: {}, repeated: {}, future100: {} };
  for (const [name, contract] of [['old', old], ['candidate', candidate]]) {
    result.first[name] = { buy: await cost(contract, 'buy', 3), drain: await cost(contract, 'drain', 3) };
    let total = 0;
    for (let i = 0; i < 8; i++) total += await cost(contract, 'buy', 3) + await cost(contract, 'drain', 3);
    result.repeated[name] = total;
    total = 0;
    for (let level = 5; level < 105; level++) total += await cost(contract, 'buy', level);
    result.future100[name] = total;
  }
  result.repeated.savedPerCycle = (result.repeated.old - result.repeated.candidate) / 8;
  result.future100.saved = result.future100.old - result.future100.candidate;
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  await provider.destroy();
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
