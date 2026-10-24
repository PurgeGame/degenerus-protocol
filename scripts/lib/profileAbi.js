import { Fragment } from "ethers";

/** Delegate workers emit events and bubble errors at their storage owner's address.
 * Keep the owner's callable surface and add only worker event/error descriptions.
 */
export function withDelegateMetadata(ownerAbi, workerAbis) {
  const fragments = new Map();
  for (const [index, abi] of [ownerAbi, ...workerAbis].entries()) {
    for (const value of abi) {
      const fragment = Fragment.from(value);
      if (index && fragment.type !== "event" && fragment.type !== "error") continue;
      const key = fragment.type + ":" + (fragment.type === "constructor"
        ? "constructor" : fragment.format("sighash"));
      if (!fragments.has(key)) fragments.set(key, JSON.parse(fragment.format("json")));
    }
  }
  return [...fragments.values()];
}
