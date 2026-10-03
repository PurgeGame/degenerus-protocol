// The fork rehearsal runs the unchanged production deployment script while
// bounding its nested force-compile task to one compiler worker.
import base from "../hardhat.config.js";
import { subtask } from "hardhat/config.js";
import { fileURLToPath } from "node:url";
import { resolve, dirname } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
subtask("compile:solidity:compile-jobs").setAction((args, hre, runSuper) =>
  runSuper({ ...args, concurrency: 1 })
);

export default {
  ...base,
  paths: {
    ...base.paths,
    root,
    sources: resolve(root, "contracts"),
    tests: resolve(root, "test"),
    cache: resolve(root, "cache"),
    artifacts: resolve(root, "artifacts"),
  },
};
