import { spawn } from "node:child_process";

console.log('\n╔════════════════════════════════════════════════════════════════╗');
console.log('║  SEPOLIA TESTNET - COMPLETE WORKFLOW                          ║');
console.log('╚════════════════════════════════════════════════════════════════╝\n');

async function runScript(scriptPath, description, env = {}) {
  console.log(`\n=== ${description} ===\n`);

  return new Promise((resolve, reject) => {
    const proc = spawn('npx', ['hardhat', 'run', scriptPath, '--network', 'sepolia'], {
      stdio: 'inherit',
      env: { ...process.env, ...env }
    });

    proc.on('close', (code) => {
      if (code === 0) {
        console.log(`\n✅ ${description} completed\n`);
        resolve();
      } else {
        console.log(`\n❌ ${description} failed with code ${code}\n`);
        reject(new Error(`${description} failed`));
      }
    });
  });
}

async function main() {
  try {
    // Step 1: Deploy contracts
    await runScript('scripts/deploy/deploy-sepolia-testnet.js', 'Step 1: Deploy Contracts');

    // Step 2: Run simulation
    console.log('\n╔════════════════════════════════════════════════════════════════╗');
    console.log('║  Starting Full Simulation                                      ║');
    console.log('╚════════════════════════════════════════════════════════════════╝\n');

    await runScript('scripts/sepolia-full-simulation.js', 'Step 2: Run Presale + Gameplay');

    console.log('\n╔════════════════════════════════════════════════════════════════╗');
    console.log('║  ALL TASKS COMPLETED SUCCESSFULLY!                             ║');
    console.log('╚════════════════════════════════════════════════════════════════╝\n');

  } catch (error) {
    console.error('\n❌ Workflow failed:', error.message);
    process.exit(1);
  }
}

main();
