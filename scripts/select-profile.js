import { selectProfile } from './lib/selectProfile.js';
import { PROFILE } from './lib/deploymentProfiles.js';
import { patchForFoundry } from './lib/patchForFoundry.js';

const check = process.argv.includes('--check');
selectProfile({ check });
if (!check && !process.argv.includes('--no-pins')) patchForFoundry();
console.log(`${PROFILE} profile ${check ? 'verified' : 'generated'}.`);
