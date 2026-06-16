#!/usr/bin/env python3
"""
v65.0 BURNIE -> FLIP deterministic rename engine.

Renames the currency token only. Preserves: the creator persona "Burnie Degenerus"
+ email, the verb "burn" (no "ie"), the "coinflip"/"flip" action, and generic "coin"
(burnCoin/mintForGame/PRICE_COIN_UNIT/IDegenerusCoin/IVaultCoin/coinflip*).

Order is load-bearing:
  0. mask creator strings so burnie->flip can't touch them
  1. the name-metadata string
  2. special contract/interface names (do NOT follow burnie->flip), longest-first, word-bounded
  3. case-preserving global burnie->flip / Burnie->Flip / BURNIE->FLIP  (catches every
     remaining token identifier incl. mid/suffix occurrences like claimAfkingBurnie)
  4. BROAD: the enumerated coin-as-the-token identifiers (word-bounded)
  5. unmask creator strings

Bare `coin`->`flip` is intentionally NOT handled here (per-occurrence judgment; do by hand).

Usage:
  python3 scripts/v65_flip_rename.py --dry  FILE [FILE ...]   # print unified diff, write nothing
  python3 scripts/v65_flip_rename.py --apply FILE [FILE ...]   # rewrite files in place
"""
import re
import sys
import difflib

CREATOR_SENT = "\x00CRTR\x00"
EMAIL_SENT = "\x00EML\x00"

# (regex, replacement) — special names that do NOT follow the plain burnie->flip rule.
SPECIAL = [
    (r'"Burnies"', '"Degenerus Gambling Token"'),
    (r'\bIBurnieCoinflipPlayer\b', 'ICoinflipPlayer'),
    (r'\bIBurnieCoinflipLinkReward\b', 'ICoinflipLinkReward'),
    (r'\bIBurnieCoinflipAffiliate\b', 'ICoinflipAffiliate'),
    (r'\bBurnieCoinflipPlayer\b', 'CoinflipPlayer'),
    (r'\bBurnieCoinflipLinkReward\b', 'CoinflipLinkReward'),
    (r'\bBurnieCoinflipAffiliate\b', 'CoinflipAffiliate'),
    (r'\bIBurnieCoinflip\b', 'ICoinflip'),
    (r'\bBurnieCoinflip\b', 'Coinflip'),
    (r'\bIBurnieCoin\b', 'IFLIP'),
    (r'\bBurnieCoin\b', 'FLIP'),
    (r'\bIBurnieTombstone\b', 'IFlipTombstone'),
    (r'\bBurnieTombstone\b', 'FlipTombstone'),
    (r'\bOnlyBurnieCoin\b', 'OnlyFLIP'),
    (r'\bonlyBurnieCoin\b', 'onlyFLIP'),
]

# plain substring, case-specific (order among them is irrelevant — distinct cases)
GLOBAL = [
    ('BURNIE', 'FLIP'),
    ('Burnie', 'Flip'),
    ('burnie', 'flip'),
]

# Stonk -> DGNRS / sDGNRS (FULL rebrand). Ordered: free up IsDGNRS first (collision fix),
# longest-first for the substring chain DegenerusStonk < StakedDegenerusStonk < IStakedDegenerusStonk.
STONK = [
    (r'\bIsDGNRS\b', 'IsDGNRSVotes'),                         # existing Admin minimal view -> frees the IsDGNRS name
    (r'\bIStakedDegenerusStonkBurn\b', 'IsDGNRSBurn'),
    (r'\bIStakedDegenerusStonk\b', 'IsDGNRS'),                # main staked interface takes the freed name
    (r'\bIDegenerusStonkWrapper\b', 'IDGNRS'),
    (r'\bOnlyStakedDegenerusStonk\b', 'OnlysDGNRS'),
    (r'"Staked Degenerus Stonk"', '"Degenerus Protocol Equity Token (staked)"'),
    (r'"Degenerus Stonk"', '"Degenerus Protocol Equity Token"'),
    (r'\bStakedDegenerusStonk\b', 'sDGNRS'),                  # concrete staked contract
    (r'\bDegenerusStonk\b', 'DGNRS'),                         # concrete liquid contract
    (r'\bstonk\b', 'staked'),                                 # local var in DGNRS.sol -> the staked token
]

# BROAD scope: coin-as-the-token identifiers (word-bounded, enumerated). Bare `coin` excluded.
BROAD = [
    (r'\bcoinOut\b', 'flipOut'),
    (r'\bcoinShare\b', 'flipShare'),
    (r'\bcoinToken\b', 'flipToken'),
    (r'\bcoinPlayer\b', 'flipPlayer'),
    (r'\bCOIN_JACKPOT_TAG\b', 'FLIP_JACKPOT_TAG'),
    (r'\bCOIN_LEVEL_TAG\b', 'FLIP_LEVEL_TAG'),
    (r'\bFAR_FUTURE_COIN_BPS\b', 'FAR_FUTURE_FLIP_BPS'),
    (r'\bFAR_FUTURE_COIN_SAMPLES\b', 'FAR_FUTURE_FLIP_SAMPLES'),
    (r'\bFAR_FUTURE_COIN_TAG\b', 'FAR_FUTURE_FLIP_TAG'),
    (r'\b_runCoinJackpot\b', '_runFlipJackpot'),
    (r'\bpayDailyCoinJackpot\b', 'payDailyFlipJackpot'),
    (r'\bredeemableCoinBacking\b', 'redeemableFlipBacking'),
    (r'\bFarFutureCoinJackpotWinner\b', 'FarFutureFlipJackpotWinner'),
]


def transform(text):
    text = text.replace("Burnie Degenerus", CREATOR_SENT)
    text = text.replace("burnie@degener.us", EMAIL_SENT)
    for pat, rep in SPECIAL:
        text = re.sub(pat, rep, text)
    for s, r in GLOBAL:
        text = text.replace(s, r)
    for pat, rep in BROAD:
        text = re.sub(pat, rep, text)
    for pat, rep in STONK:
        text = re.sub(pat, rep, text)
    text = text.replace(CREATOR_SENT, "Burnie Degenerus")
    text = text.replace(EMAIL_SENT, "burnie@degener.us")
    return text


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("--dry", "--apply"):
        print(__doc__)
        sys.exit(2)
    mode, files = sys.argv[1], sys.argv[2:]
    changed = 0
    for path in files:
        with open(path, "r") as f:
            src = f.read()
        out = transform(src)
        if out == src:
            continue
        changed += 1
        if mode == "--dry":
            diff = difflib.unified_diff(
                src.splitlines(keepends=True), out.splitlines(keepends=True),
                fromfile=path, tofile=path + " (renamed)")
            sys.stdout.writelines(diff)
        else:
            with open(path, "w") as f:
                f.write(out)
            print(f"rewrote {path}")
    print(f"\n{changed}/{len(files)} files changed")


if __name__ == "__main__":
    main()
