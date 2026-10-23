#!/usr/bin/env python3
"""Reviewed RNG migration rules. Inventory is emitted before --apply changes sources."""
import argparse
import json
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from rng_taint_extract import strip_comments_and_strings, enclosing_functions, param_list

rules = []
def rule(file, old, new, reason):
    rules.append(dict(file='contracts/' + file + '.sol', old=old, new=new, reason=reason))
def h(tag, *args):
    return f'EntropyLib.hash{len(args)+1}(RngTags.{tag}, ' + ', '.join(args) + ')'
def r(file, old, tag, args, reason):
    rule(file, old, h(tag, *args), reason)

r('Coinflip', 'keccak256(abi.encodePacked(BAF_DRAW_TAG, address(this), day, rngWord))', 'BAF_HEAD', ['rngWord'], 'One BAF head draw per transition word; host address and the closed book day separate no second draw.')
r('WWXRP', 'keccak256(abi.encodePacked(DOM_INCIN_WINNER, address(this), bracket, rngWord))', 'WWXRP_INCINERATOR', ['rngWord'], 'One skipped BAF bracket per transition word; address and bracket are redundant.')
rule('WWXRP', 'keccak256(abi.encodePacked(domain, address(this), day, word))', 'EntropyLib.hash2(uint256(domain), word)', 'Private wrapper is replaced by direct calls with constant tags; one daily draw per word.')
r('DegenerusGame', 'EntropyLib.hash2(entropy, attempt)', 'BAF_FUTURE_ATTEMPT', ['entropy', 'attempt'], 'Attempt separates up to twelve selections; the input is the tagged pair seed.')
r('DegenerusJackpots', 'EntropyLib.hash2(_bafEntropyBase(rngWord), BAF_HEAD_PICK_KEY)', 'BAF_HEAD_SIDE', ['rngWord'], 'A separate action tag replaces the intermediate BAF base and head key.')
r('DegenerusJackpots', 'EntropyLib.hash2(base, round)', 'BAF_NEAR_ROUND', ['rngWord', 'round'], 'Round separates repeated four-candidate samples from the same BAF word; remove intermediate base.')
r('DegenerusJackpots', 'EntropyLib.hash2(base, BAF_FAR_PAIR_KEY | pair)', 'BAF_FAR_PAIR', ['rngWord', 'pair'], 'Pair separates repeated eight-candidate samples; action tag replaces packed domain key and intermediate base.')
rule('DegenerusJackpots', 'EntropyLib.hash2(rngWord, uint256(BAF_WINNERS_TAG))', 'rngWord', 'Remove unused intermediate hash after direct action derivations.')
for fn, tag in [('DAILY_QUEST_TAG','QUEST_DAILY'),('LEVEL_QUEST_TAG','QUEST_LEVEL')]:
    r('DegenerusQuests', f'EntropyLib.hash2(entropy, uint256({fn}))', tag, ['entropy'], 'One quest of this kind per word; constant action domain only.')
r('libraries/FlipRoundLib', 'keccak256(abi.encodePacked(REWARD_PERCENT_TAG, rngWord, epoch))', 'FLIP_REWARD', ['rngWord'], 'Daily word and separately tagged redemption flip each identify one reward draw; epoch separates nothing.')
for old,tag,args,reason in [
    ('keccak256(abi.encode(SAMPLE_TAG, word, lvl))','DECIMATOR_ROTATION',['word'],'Only one active Decimator round per session word; level is redundant.'),
    ('keccak256(abi.encode(SAMPLE_TAG, word, lvl, stratum))','DECIMATOR_SAMPLE',['word','stratum'],'Stratum separates independent samples; one active round per word.')]:
    r('libraries/DecimatorSamplingLib',old,tag,args,reason)
r('libraries/GoldSixLib','EntropyLib.hash2(seed, REPLACEMENT_TAG)','GOLD_REPLACEMENT',['seed'],'Shared gold-six replacement action on its tagged parent seed.')
r('libraries/GoldSixLib','EntropyLib.hash2(word, DAILY_TAG)','GOLD_DAILY',['word'],'Separate action for retaining daily gold-six.')
r('libraries/JackpotBucketLib','EntropyLib.hash2(rw, uint256(TRAIT_BOARD_TAG))','JACKPOT_BOARD',['rw'],'One main four-quadrant board per word; bit slices are one joint board outcome.')
r('libraries/PackedTicketSampleLib','EntropyLib.hash2(c.entropy, used)','SAMPLE_PADDING',['c.entropy','used'],'Lane discriminator separates padding redraws within the same eight-lane sample.')
r('libraries/TicketEntropy','EntropyLib.hash4(ROTATION_DOMAIN, queueKey, total, entropy)','TICKET_ROTATION',['entropy','queueKey'],'Queue key separates ordinary/future queues at several levels under one word. Frozen total is only the modulus, not a discriminator.')
r('libraries/TicketEntropy','keccak256(abi.encode(REMAINDER_DOMAIN, stream, entropy))','TICKET_REMAINDER',['entropy','stream & ~(uint256(type(uint32).max) << ID_SHIFT)'],'Stream domain, level, queue position and offset identify a run; wallet ID is redundant with immutable queue position.')
for old,tag in [('SKIM_BPS_TAG','POOL_SKIM'),('SKIM_VARIANCE_TAG','POOL_VARIANCE_A'),('FUTURE_KEEP_TAG','POOL_FUTURE_KEEP')]:
    r('modules/DegenerusGameAdvanceModule',f'EntropyLib.hash2(rngWord, uint256({old}))',tag,['rngWord'],'One pool action per daily word.')
r('modules/DegenerusGameAdvanceModule','EntropyLib.hash1(varianceWord)','POOL_VARIANCE_B',['rngWord'],'Second independent variance draw derives directly from the word instead of rehashing the first.')
r('modules/DegenerusGameBoonModule','keccak256(abi.encode(PROTOCOL_BOON_WINNER_TAG, issuer, day, slot, winnerWord))','PROTOCOL_BOON_WINNER',['winnerWord','issuerId','slot'],'Issuer ID separates the two protocol pools; slot separates three awards. Address and day are redundant.')
r('DegenerusGameLens','keccak256(abi.encode(PROTOCOL_BOON_WINNER_TAG, issuer, day, slot, word))','PROTOCOL_BOON_WINNER',['word','issuer == ContractAddresses.VAULT ? VAULT_WALLET_ID : SDGNRS_WALLET_ID','slot'],'Mirror exactly the settlement issuer ID and slot; daily word identifies award day.')
r('modules/DegenerusGameBoonModule','EntropyLib.hash2(seed, nonceBase + i)','BOX_BOON_LANE',['seed','nonceBase + i'],'Nonce separates the fixed boon draws belonging to this box entry.')
for file,word,slot in [('modules/GameBoonActions','rngWord','slot'),('DeityBoonViewer','dailySeed','i')]:
    r(file,f'keccak256(abi.encode({word}, uint256(deityId), day, {slot}))','DEITY_MENU',[word,'(uint256(deityId) << 24) | day',slot],'Issuer and slot separate menus. Day is REQUIRED: absent predecessor fallback uses the award-day word, which can also serve the following day menu.')
for old,tag,args,reason in [
    ('keccak256(abi.encode(GEN_DRAW_TAG, word, lvl, id, q, trait))','DECIMATOR_OWNER',['word','id'],'Generated ID already uniquely selects its quadrant and trait; one active round per word.'),
    ('keccak256(abi.encode(BOARD_TAG, word, lvl, id))','DECIMATOR_BOARD',['word','id'],'Entry ID separates paid/generated boards; one active round per word.'),
    ('keccak256(abi.encode(DICE_TAG, word, lvl))','DECIMATOR_DICE',['word'],'All entries intentionally share the round dice; one round per word.'),
    ('keccak256(abi.encode(GEN_PLAYER_TAG, word, lvl, id))','DECIMATOR_GENERATED',['word','id'],'Generated ID separates synthetic survival owners; level is redundant.'),
    ('keccak256(abi.encode(TIE_TAG, word, lvl, id))','DECIMATOR_TIE',['word','id'],'Entry ID separates tie priorities; level is redundant.')]:
    r('modules/DegenerusGameDecimatorModule',old,tag,args,reason)
r('DegenerusGameLens','keccak256(abi.encode(tag, rngWord, lvl, id))','DECIMATOR_TIE',['rngWord','id'],'Exact mirror of Decimator tie ordering.')
for old,tag in [('BET_SURVIVAL_TAG','BET_SURVIVAL'),('FLIP_ROUND_TAG','BET_ROUND'),('RECORD_SPIN_TAG','BET_RECORD')]:
    r('modules/DegenerusGameDegeneretteModule',f'EntropyLib.hash4(rngWord, c.playerId, betId, {old})',tag,['rngWord','betId'],'Bet ID is unique inside the word cohort and determines its owner; remove redundant owner ID.')
r('modules/DegenerusGameDegeneretteModule','EntropyLib.hash2(rngWord, betId)','BET_BOX',['rngWord','betId'],'Separate bet reward-box action; bet ID distinguishes concurrent bets.')
r('modules/DegenerusGameDegeneretteModule','EntropyLib.hash4(rngWord, index, symbol, spinIdx)','BET_PLAYER',['rngWord','symbol','spinIdx'],'One index cohort per word; bettors choosing a symbol intentionally share player tickets. Spin position separates rounds.')
for old,tag in [('WWXRP_RIG_SALT','SPIN_RIG'),('PLAYER_TICKET_TAG','SPIN_PLAYER'),('HERO_PICK_TAG','SPIN_HERO'),('RESULT_TICKET_TAG','SPIN_HOUSE'),('BOX_SURVIVAL_TAG','SPIN_SURVIVAL'),('FLIP_ROUND_TAG','SPIN_ROUND'),('BOX_RECIRC_TAG','SPIN_RECIRC')]:
    for value in (['seed','ss'] if old=='RESULT_TICKET_TAG' else ['seed']):
        r('modules/DegenerusGameDegeneretteModule',f'EntropyLib.hash2({value}, {old})',tag,[value],'Named shared spin stage on an already independently keyed entry/spin seed.')
r('modules/DegenerusGameDegeneretteModule','EntropyLib.hash2(rigSeed, 1)','SPIN_RIG_PICK',['rigSeed'],'Separate rig-selection stage after the rig-admission draw.')
rule('modules/DegenerusGameDegeneretteModule','EntropyLib.hash2(seed, WWXRP_DRAW_TAG)','seed','WWXRP route already supplies a unique tagged entry seed; remove a redundant route-only rehash.')
r('modules/DegenerusGameDegeneretteModule','EntropyLib.hash2(seed, i)','SPIN_FLIP_ROUND',['seed','i'],'Spin position separates the three automatic FLIP spins.')
r('modules/DegenerusGameDegenesisModule','EntropyLib.hash4(DEGENESIS_ORDER_DOMAIN, g.word, (g.day << 32) | index, o.id)','DEGENESIS_ORDER',['g.word','index'],'prepareDegenesis binds one nonempty cohort per request; index uniquely determines recipient. Day and owner ID are redundant.')
for old,tag in [('DEGENESIS_CATEGORY_TAG','DEGENESIS_CATEGORY'),('DEGENESIS_SIZE_TAG','DEGENESIS_SIZE'),('FLIP_ROUND_TAG','DEGENESIS_ROUND'),('DEGENESIS_PASS_TAG','DEGENESIS_PASS'),('BOX_PASS_ROUND_TAG','DEGENESIS_PASS_ROUND')]:
    r('modules/DegenerusGameDegenesisModule',f'EntropyLib.hash2(seed, {old})',tag,['seed'],'Distinct action on the tagged per-order seed; no additional discriminator needed.')
r('modules/DegenerusGameFoilCore','keccak256(abi.encode(entropy, uint256(buyerId), lvl, FOIL_SEED_TAG, i))','FOIL_LINES',['entropy','(uint256(buyerId) << 24) | lvl','i'],'A word serves packs at several levels; one pack per wallet per level and four lines per pack require all three key fields.')
for old,tag in [('FOIL_CCY_TAG','FOIL_CURRENCY'),('FOIL_SPIN_TAG','FOIL_SPIN')]:
    r('modules/DegenerusGameFoilCore',f'keccak256(abi.encode(entropy, day, ticketIndex, {old}))',tag,['entropy','ticketIndex'],'Stored entropy already belongs to one daily draw; ticket index distinguishes its eight claim lines. Preserve existing shared line outcomes across accounts.')
r('storage/DegenerusGameStorage','keccak256(abi.encode(rngWord, day, FOIL_PAYOUT_SEED_TAG))','FOIL_PAYOUT',['rngWord'],'One foil payout seed per daily word; packed day remains a record authentication field only.')
for old,tag,args,reason in [
    ('keccak256(abi.encode(randomWord, FLIP_LEVEL_TAG, pull))','FLIP_LEVEL',['randomWord','pull'],'Pull separates the sampled levels.'),
    ('keccak256(abi.encode(rngWord, lvl, FAR_FUTURE_FLIP_TAG))','FUTURE_BATTLE',['rngWord'],'Only one purchase jackpot battle per daily word.'),
    ('EntropyLib.hash2(word, walk.ordinal++)','FUTURE_BATTLE_VISIT',['word','walk.ordinal++'],'Ordinal separates level visits and remains checkpoint independent.'),
    ('EntropyLib.hash4(word, lvl, BAF_TICKET_TAG, i)','BAF_TICKET',['word','i'],'One BAF transition per word; award index separates repeated winners, level is redundant.'),
    ('EntropyLib.hash2(entropy, entropy)','JACKPOT_TICKET_ROLL',['entropy'],'Tagged ticket conversion replaces self-mixing of the identical seed.')]:
    r('modules/DegenerusGameJackpotDrawModule',old,tag,args,reason)
r('modules/DegenerusGameJackpotDrawUtils','EntropyLib.hash4(randomWord, trait, salt, pull)','BUCKET_SAMPLE',['randomWord','salt','pull'],'Salt separates action/quadrant streams and pull separates eight-lane samples; the trait is already fixed by that stream.')
for old,arg in [('EntropyLib.hash2(word, work.lvl)','work.lvl'),('EntropyLib.hash2(word, level)','level')]:
    r('modules/DegenerusGameJackpotModule',old,'JACKPOT_ALLOCATION',['word',arg],'Level REQUIRED: current and next-level allocations share one word; BAF/main/solo helpers intentionally share the same allocation.')
for value,q in [('entropy','q'),('entropy','d.solo'),('plan.entropy','q')]:
    r('modules/DegenerusGameJackpotModule',f'EntropyLib.hash2({value}, {q})','JACKPOT_QUADRANT',[value,q],'Quadrant separates recipient streams on a shared level allocation seed.')
r('modules/DegenerusGameJackpotModule','keccak256(abi.encode(entropy, HERO_SYMBOL_TAG, day))','JACKPOT_HERO',['entropy'],'One hero selection per daily word; day is redundant.')
r('modules/DegenerusGameJackpotModule','keccak256(abi.encodePacked(randWord, DAILY_CURRENT_BPS_TAG, counter))','JACKPOT_DAILY_BPS',['randWord'],'One daily percentage draw per word; counter sizes no independent second outcome.')
r('modules/DegenerusGameLootboxModule','EntropyLib.hash4(c.rootWord, uint256(c.id), BOX_BOON_TAG, boonIndex)','BOX_BOON',['c.rootWord'],'One boon stream per order root. The root fixes queued position or redemption beneficiary; the physical buffer/batch and owner add no discriminator. Per-box boon nonces remain in BOX_BOON_LANE.')
r('modules/DegenerusGameLootboxModule','EntropyLib.hash4(c.rootWord, uint256(c.id), BOX_OPEN_TAG, ++c.nonce)','BOX_OPEN',['c.rootWord','++c.nonce'],'Root identifies the entry; nonce separates boxes inside it. Owner ID is redundant.')
r('modules/DegenerusGameLootboxModule','EntropyLib.hash4(QUEUED_ORDER_DOMAIN, rngWord, buffer, position)','BOX_ORDER',['rngWord','position'],'One sealed queue buffer per word; entry position is REQUIRED even for repeat purchases by the same owner.')
r('modules/DegenerusGameLootboxModule','EntropyLib.hash2(rngWord, uint256(id))','BOX_DIRECT',['rngWord'],'All internal callers provide an independently tagged bet/redemption/recirculation seed which already determines the owner.')
r('modules/DegenerusGameLootboxModule','EntropyLib.hash4(rngWord, uint256(id), AFKING_BOX_TAG, day)','BOX_AFKING',['rngWord','uint256(id)'],'One stamped AFKing open per subscriber per active session word; ID separates subscribers, stamped day does not separate additional opens.')
for old,tag,var in [('FLIP_ROUND_TAG','BOX_ROUND','rollSeed'),('BOX_WWXRP_SPIN_TAG','BOX_WWXRP_SPIN','seed'),('BOX_FLIP_SPIN_TAG','BOX_FLIP_SPIN','seed'),('BOX_ETH_SPIN_TAG','BOX_ETH_SPIN','seed'),('BOX_PASS_ROUND_TAG','BOX_PASS_ROUND','seed'),('BOX_PASS_SPIN_TAG','BOX_PASS_SPIN','seed')]:
    r('modules/DegenerusGameLootboxModule',f'EntropyLib.hash2({var}, {old})',tag,[var],'Distinct box action, entry identity is already in its parent seed.')
r('modules/DegenerusGameRngUtils','keccak256(abi.encodePacked(vrfWord, yesterday))','GAP_DAY',['vrfWord','yesterday'],'Day REQUIRED: one recovery word backfills several daily outcomes.')
for old,tag,args,reason in [
    ('EntropyLib.hash4(DIRECT_TICKET_DOMAIN, plan.entropy, (uint256(q) << 32) | i, round)','TICKET_DIRECT',['plan.entropy','(uint256(q) << 32) | i','round'],'Source quadrant/group and award round each distinguish multiple outputs.'),
    ('EntropyLib.hash2(plan.entropy, q)','JACKPOT_QUADRANT',['plan.entropy','q'],'Same logical quadrant stream as daily planning.'),
    ('EntropyLib.hash4(seed, trait, uint8(plan.salt + q), start + j)','BUCKET_SAMPLE',['seed','uint8(plan.salt + q)','start + j'],'Exact shared bucket sampler; trait is already determined by its stream.'),
    ('EntropyLib.hash2(seed, q + 4)','TICKET_SHUFFLE',['seed','q'],'Quadrant separates independent permutations; +4 domain replaced by action tag.'),
    ('EntropyLib.hash2(entropy, left)','TICKET_SHUFFLE_STEP',['entropy','left'],'Remaining position separates Fisher-Yates steps within this quadrant.'),
    ('EntropyLib.hash2(seed, base / 8)','TICKET_GROUP',['seed','base / 8'],'Packed group position separates trait words; quadrants consume distinct bit slices.'),
    ('keccak256(abi.encode(baseKey, entropyWord, groupIdx))','TICKET_TRAITS',['entropyWord','baseKey & ~(uint256(type(uint32).max) << TicketEntropy.ID_SHIFT)','groupIdx'],'Domain/level/queue position distinguish streams, group distinguishes aligned sixteen-entry groups; owner is fixed by position.'),
    ('keccak256(abi.encode(lvl, round, entropy))','TICKET_ROUND',['entropy','lvl','round'],'Word serves several levels and rounds at each level; both discriminators are required.')]:
    r('modules/DegenerusGameTicketModule',old,tag,args,reason)
rule('modules/DegenerusGameWhaleModule','EntropyLib.hash4(randWord, uint256(ticketLeg ? TICKET_WHALE_TAG : QUADRANT_WHALE_TAG), dailyIdx, lvl)', 'EntropyLib.hash2(ticketLeg ? RngTags.WHALE_TICKET : RngTags.WHALE_QUADRANT, randWord)', 'Parent seed already keys level/quadrant; distinct constant action tags separate award legs. Day/level separate nothing.')
rule('modules/DegenerusGameWhaleModule','EntropyLib.hash2(entropy, 1)','entropy','Remove needless rehash of the tagged whale recipient draw.')
r('modules/GameAfkingModule','keccak256(abi.encodePacked("SEATDRAW", word))','SUBSCRIBER_DRAW',['word'],'One subscriber draw per daily word; named fixed-width tag replaces string packing.')
r('sDGNRS','keccak256(abi.encodePacked(SYNTH_FLIP_TAG, word, id))','REDEMPTION_FLIP',['word'],'Exactly one redemption batch closes at each request, so batch ID is redundant.')
r('sDGNRS','EntropyLib.hash2(rngWord, uint256(CENTURY_REFILL_TAG) ^ completedLevel)','CENTURY_REFILL',['rngWord'],'One century transition per word; remove level and XOR domain mixing.')
r('sDGNRS','EntropyLib.hash2(word, uint256(walletId))','REDEMPTION_BOX',['word','uint256(walletId)'],'Many beneficiaries share one batch word, wallet ID is required.')

for file in ['CrapsBattle','JackpotBattle']:
    r(file,'_hash3(word, SCHEDULE_TAG, period == _BONUS_PERIODS_PER_DAY - 2 ? 0 : period)','CRAPS_SCHEDULE',['word','period == _BONUS_PERIODS_PER_DAY - 2 ? 0 : period'],'Periods share a day word; the two bookends intentionally share period zero terms.')
    r(file,'_hash3(word, bound, BOOST_TAG)','CRAPS_BOOST',['word','bound'],'Several scheduled/custom slots can share one settling word; bound is required.')
for who in ['challenger','leader']:
    r('CrapsBattle',f'_hash3(word, TIE_TAG, field | {who})','CRAPS_TIE',['word',f'field | {who}'],'Packed field and seat ID distinguish simultaneous fields and entrants under one word.')
for old,tag,args,reason in [
    ('_hash3(word, JACKPOT_AWARDED_TAG, betId)','CRAPS_AWARDED',['word','betId'],'Repeated awards to one wallet remain distinct synthetic owners.'),
    ('_hash3(uint256(_CRAPS_SEED_DOMAIN), word, bound)','CRAPS_DICE',['word','bound'],'Slots sharing a word require distinct table dice; seats within each table intentionally share dice.'),
    ('_hash2(ROTATING_SHOOTER_TAG, uint256(seed))','CRAPS_SHOOTER',['uint256(seed)'],'One rotating shooter draw for this tagged field seed.'),
    ('_hash3(word, SCATTER_TAG, key)','CRAPS_BOARD',['word','key'],'Required owner/synthetic-entry key separates board scatter.'),
    ('_hash3(word, CRAPS_ROUND_TAG, betId)','CRAPS_ROUND',['word','betId'],'Per-bet payment rounding stays independent of other bets.')]:
    r('CrapsEngine',old,tag,args,reason)
r('JackpotBattle','keccak256(abi.encode(_CRAPS_SEED_DOMAIN, word, uint256(slot)))','CRAPS_DICE',['word','uint256(slot)'],'Exact table dice mirror used for shooter attribution; slot required across simultaneous tables.')
r('JackpotBattle','keccak256(abi.encode(uint256(0x526f746174696e6753686f6f746572), seed))','CRAPS_SHOOTER',['seed'],'Exact shooter attribution mirror.')
r('JackpotBattle','_hash2(word, JACKPOT_MULT_TAG)','CRAPS_JACKPOT_MULT',['word'],'One purchase jackpot multiplier per daily word.')
r('JackpotBattle','_hash3(word, _activeJackpotSlot, JACKPOT_SUBSIDY_TAG)','CRAPS_SUBSIDY',['word'],'Only one active purchase jackpot per word; slot is redundant.')
r('JackpotBattle','_hash3(r.drawWord, HIGH_RESERVE_WINNER_TAG, (uint256(slot) << 32) | draw.eligible)','CRAPS_RESERVE_WINNER',['r.drawWord','(uint256(slot) << 32) | draw.eligible'],'Slot and eligible ordinal distinguish reservoir steps across multiple fields sharing a word.')
r('JackpotBattle','_hash3(r.drawWord, HIGH_RESERVE_DRAW_TAG, slot)','CRAPS_RESERVE_DRAW',['r.drawWord','slot'],'Independent reserve admission per slot under a shared word.')
r('storage/CrapsBattleStorage','_hash2(word, HIGH_TAG)','CRAPS_HIGH',['word'],'One published high-roller multiple per daily word.')

def compact(s):
    return re.sub(r'\s+', '', s)
def find_expression(source, old):
    pattern = r'\s*'.join(map(re.escape, re.findall(r'\w+|[^\w\s]', old)))
    return list(re.finditer(pattern, source))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--apply',action='store_true');a=p.parse_args()
    inventory=[]
    for row in rules:
        source=Path(row['file']).read_text(); matches=find_expression(source,row['old'])
        if not matches: raise SystemExit('Missing reviewed expression: '+str(row))
        for match in matches:
            inventory.append(dict(row,line=source.count('\n',0,match.start())+1))
    dest=Path('.planning/consolidation/rngclean');dest.mkdir(parents=True,exist_ok=True)
    (dest/'inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
    (dest.parent/'RNGCLEAN-INVENTORY.md').write_text('# RNG derivation inventory\n\nPinned base: `67f8b9582`. Reviewed before production edits.\n\n'
        'All rows consume a sealed request word or an explicitly tagged parent action seed. The word itself stays unchanged in storage.\n\n'
        '| Source | Before | After | Input classification and removal proof |\n|---|---|---|---|\n'+''.join(
        f"| {v['file']}:{v['line']} | `{v['old'].replace('|','&#124;')}` | `{v['new'].replace('|','&#124;')}` | {v['reason']} |\n" for v in inventory))
    print('Reviewed hash sites:',len(inventory),flush=True)
    if not a.apply:return
    for row in rules:
        path=Path(row['file']);source=path.read_text()
        for match in reversed(find_expression(source,row['old'])):source=source[:match.start()]+row['new']+source[match.end():]
        path.write_text(source)

if __name__=='__main__':main()
