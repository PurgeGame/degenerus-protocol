import { expect } from "chai";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { patchContractAddresses } from "../../scripts/lib/patchContractAddresses.js";

describe("Deployment optional configuration isolation", function () {
  let scratch;
  let target;
  const zero = "0x0000000000000000000000000000000000000000";
  const pinned = {
    LINK_ETH_FEED: "0x0000000000000000000000000000000000001234",
    ENS_REVERSE_REGISTRAR: "0x0000000000000000000000000000000000005678",
  };

  beforeEach(function () {
    scratch = mkdtempSync(join(tmpdir(), "degenerus-config-test-"));
    target = join(scratch, "ContractAddresses.sol");
    writeFileSync(target, readFileSync(new URL("../../contracts/ContractAddresses.sol", import.meta.url)));
    patchContractAddresses(new Map(), pinned, 20699, null, target);
  });

  afterEach(function () {
    rmSync(scratch, { recursive: true, force: true });
  });

  function assertAddresses(expected) {
    const source = readFileSync(target, "utf8");
    for (const [key, value] of Object.entries(expected)) {
      expect(source).to.match(new RegExp(`${key} =\\s*address\\(${value}\\)`));
    }
  }

  it("installs explicitly configured integrations", function () {
    assertAddresses(pinned);
  });

  it("clears both integrations when the next build omits them", function () {
    patchContractAddresses(new Map(), {}, 20700, null, target);
    assertAddresses({ LINK_ETH_FEED: zero, ENS_REVERSE_REGISTRAR: zero });
  });

  it("resets an empty integration while retaining the explicitly selected feed", function () {
    patchContractAddresses(new Map(), {
      LINK_ETH_FEED: pinned.LINK_ETH_FEED,
      ENS_REVERSE_REGISTRAR: "",
    }, 20700, null, target);
    assertAddresses({ LINK_ETH_FEED: pinned.LINK_ETH_FEED, ENS_REVERSE_REGISTRAR: zero });
  });
});
