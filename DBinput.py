import sqlite3,urllib.request
import json, time
from web3 import Web3
import asyncio
import os

address = '0x6055d67660B7749De625021BA0DEc8d7d2B96B8f'
offset = 420

ALCHEMY_API = os.environ.get("ALCHEMY_API")
ETHERSCAN_API_ONE = os.environ.get("ETHERSCAN_API_ONE")

alchemy_url = 'https://eth-rinkeby.alchemyapi.io/v2/'+ALCHEMY_API
web3 = Web3(Web3.HTTPProvider(alchemy_url))


ESAPI = 'https://api-rinkeby.etherscan.io/api?module=contract&action=getabi&address=' + address + '&apikey=' + ETHERSCAN_API_ONE
with urllib.request.urlopen(ESAPI) as url:
    data = url.read().decode()
    contractabi = json.loads(data)['result']
address = Web3.toChecksumAddress(address)
contract = web3.eth.contract(address= address, abi=contractabi)



def purgetime(block):
    # purgeTime = web3.eth.getblock(block)
    # purgeTime = purgeTime['timestamp']
    purgeTime = int(time.time())
    return (purgeTime)

def getTransfer(new, filter, fromblock):
    Transfer = contract.events.Transfer()
    if new == 0:
        filter = Transfer.createFilter(fromBlock = fromblock)
        Transfers = filter.get_all_entries()
    else:
        Transfers =filter.get_new_entries()
    return(Transfers, filter)

def getMAP(fromblock):
    MintAndPurge = contract.events.MintAndPurge()
    filter = MintAndPurge.createFilter(fromBlock = fromblock)
    MintAndPurges = filter.get_all_entries()
    return (MintAndPurges)

def getMints(fromblock):
    TokenMinted = contract.events.TokenMinted()
    filter = TokenMinted.createFilter(fromBlock = fromblock)
    mints = filter.get_all_entries()
    return(mints)

def getReferrals(new, filter,fromblock):
    Referred = contract.events.Referred()
    if new == 0:
        conn = sqlite3.connect('PurgeGame.db')
        cur = conn.cursor()
        cur.execute('DROP TABLE IF EXISTS referrals')
        cur.execute("""CREATE TABLE referrals (
        address TEXT,
        referralcode TEXT,
        referee TEXT,
        number INTEGER
        )""")
        conn.commit
        conn.close
        filter = Referred.createFilter(fromBlock = fromblock)
        ref = filter.get_all_entries()
    else:
        ref = filter.get_new_entries()
    return(ref, filter)

def importmint():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    mints = getMints(0)
    end = 0 
    totalMints = contract.caller.totalMinted()
    if len(mints) > 9500:
        end = mints[9500]['blockNumber']
    c=0
    while c < len(mints):
        if mints[c]['blockNumber']-1 == end:
            fromblock = end-1
            mints = getMints(fromblock)
            if len(mints) > 9500:
                end = mints[9500]['blockNumber']
            c = 0
        else:
            tokenTraits = mints[c]['args']['tokenTraits']
            tokenTraitOne = tokenTraits & 0x3f
            tokenTraitTwo = ((tokenTraits & 0xfc0) >> 6) + 64
            tokenTraitThree = ((tokenTraits & 0x3f000) >> 12) + 128
            tokenTraitFour = ((tokenTraits & 0xfc0000) >> 18) + 192
            tokenId = mints[c]['args']['tokenId']
            if tokenId-offset < 1 :
                realtokenId = totalMints - (offset - tokenId)
            else:
                realtokenId = tokenId - offset
            holder = mints[c]['args']['from']
            tokenData = [str(realtokenId),tokenTraitOne,tokenTraitTwo,tokenTraitThree,tokenTraitFour]
            cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
            {'tokenId':int(tokenData[0]), 'trait1':int(tokenData[1]), 'trait2':int(tokenData[2]),'trait3':int(tokenData[3]),'trait4': int(tokenData[4]),
            'holderaddress':holder,'purgeaddress':0,'purgetime':0,'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/' + tokenData[0] +'.png'})
        c+=1
    conn.commit()
    conn.close

def importmap():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    fromblock = 1
    MintAndPurges = getMAP(fromblock)
    end = 0
    if len(MintAndPurges) > 9500:
        end = MintAndPurges[9500]['blockNumber']
    c =0
    while c< len(MintAndPurges):
        if MintAndPurges[c]['blockNumber']-1 == end:
            fromblock = end-1
            MintAndPurges = getMAP(fromblock)
            if len(MintAndPurges) > 9500:
                end = MintAndPurges[9500]['blockNumber']
            c = 0
        else:
            tokenTraits = MintAndPurges[c]['args']['tokenTraits']
            tokenTraitOne = tokenTraits & 0x3f
            tokenTraitTwo = ((tokenTraits & 0xfc0) >> 6) + 64
            tokenTraitThree = ((tokenTraits & 0x3f000) >> 12) + 128
            tokenTraitFour = ((tokenTraits & 0xfc0000) >> 18) + 192
            tokenId = MintAndPurges[c]['args']['tokenId']
            purgeAddress = MintAndPurges[c]['args']['from']
            block = MintAndPurges[c]['blockNumber']
            purgeTime = purgetime(block)
            tokenData = [str(tokenId),tokenTraitOne,tokenTraitTwo,tokenTraitThree,tokenTraitFour,purgeAddress,purgeTime]
            cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
            {'tokenId':int(tokenData[0]), 'trait1':int(tokenData[1]), 'trait2':int(tokenData[2]),'trait3':int(tokenData[3]),'trait4': int(tokenData[4]),
            'holderaddress':0,'purgeaddress':tokenData[5],'purgetime':int(tokenData[6]),'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/' + tokenData[0] +'.png'})
        c+=1
    conn.commit()
    conn.close  


def countTraits():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    for c in range (0,64):
        cur.execute("""
            SELECT COUNT(trait1)
            FROM tokens
            WHERE trait1 = ?""",(c,))
        traitcount = cur.fetchone()
        cur.execute(
            """UPDATE traits SET total = ?, remaining = ?
            WHERE trait = ?""",(traitcount[0],traitcount[0],c))
    for c in range (64,128):
        cur.execute("""
            SELECT COUNT(trait1)
            FROM tokens
            WHERE trait2 = ?""",(c,))
        traitcount = cur.fetchone()
        cur.execute(
            """UPDATE traits SET total = ?, remaining = ?
            WHERE trait = ?""",(traitcount[0],traitcount[0],c))
    for c in range(128,192):
        cur.execute("""
            SELECT COUNT(trait1)
            FROM tokens
            WHERE trait3 = ?""",(c,))
        traitcount = cur.fetchone()
        cur.execute(
            """UPDATE traits SET total = ?, remaining = ?
            WHERE trait = ?""",(traitcount[0],traitcount[0],c))
    for c in range(192,256):
        cur.execute("""
            SELECT COUNT(trait1)
            FROM tokens
            WHERE trait4 = ?""",(c,))
        traitcount = cur.fetchone()
        cur.execute(
            """UPDATE traits SET total = ?, remaining = ?
            WHERE trait = ?""",(traitcount[0],traitcount[0],c))
    conn.commit()
    conn.close 

def removetraits(_tokenId,conn):
    cur = conn.cursor()
    cur.execute("""
        SELECT *
        FROM tokens
        WHERE tokenId = ?""",(_tokenId,))
    tokeninfo = cur.fetchone()
    for c in range (1,5):
        _trait = tokeninfo[c]
        cur.execute("""
            SELECT remaining 
            FROM traits 
            WHERE trait = ?""",(_trait,))
        traitremaining = cur.fetchone()[0]
        if _trait <64:
            cur.execute(
                """UPDATE tokens SET trait1purge = ?
                WHERE tokenId = ?""",(traitremaining,_tokenId))
        elif _trait <128:
            cur.execute(
                """UPDATE tokens SET trait2purge = ?
                WHERE tokenId = ?""",(traitremaining,_tokenId))
        elif _trait <192:
            cur.execute(
                """UPDATE tokens SET trait3purge = ?
                WHERE tokenId = ?""",(traitremaining,_tokenId))
        elif _trait <256:
            cur.execute(
                """UPDATE tokens SET trait4purge = ?
                WHERE tokenId = ?""",(traitremaining,_tokenId))
        traitremaining -= 1
        cur.execute(
            """UPDATE traits SET remaining = ?
            WHERE trait = ?""",(traitremaining,_trait))
    conn.commit()
    conn.close

def mapPurge():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
        SELECT tokenId 
        FROM tokens 
        WHERE holderaddress = 0""")
    maps = cur.fetchall()
    for row in maps:
        removetraits(row[0], conn)
    conn.close

def transfer():
    fromblock = 0
    transfer = getTransfer(0,0,fromblock)
    filter = transfer[1]
    transfer = transfer[0]
    end = 0
    x=0
    while 1:
        if len(transfer) > 0:
            conn = sqlite3.connect('PurgeGame.db')
            cur = conn.cursor()
        if len(transfer) > 9000:
            end = transfer[9000]['blockNumber']
        c=0
        while c< len(transfer):
            if transfer[c]['blockNumber'] == end:
                fromblock = end
                transfer = getTransfer(0,0,fromblock)[0]
                if len(transfer) > 9000:
                    end = transfer[9000]['blockNumber']
                else:
                    end = 0
                c=0
            else:
                if transfer[c]['args']['to'] == '0x0000000000000000000000000000000000000000':
                    block = transfer[c]['blockNumber']

                    purgeTime = purgetime(block)
                    cur.execute(
                        """UPDATE tokens SET purgetime = ?, purgeaddress = ?, holderaddress = 0
                        WHERE tokenId = ?""",(purgeTime,transfer[c]['args']['from'],transfer[c]['args']['tokenId']))
                    removetraits(transfer[c]['args']['tokenId'],conn)
                else:
                    cur.execute(
                        """UPDATE tokens SET holderaddress = ?
                        WHERE tokenId = ?""",(transfer[c]['args']['to'],transfer[c]['args']['tokenId']))
            c+=1
        conn.commit()
        conn.close
        time.sleep(30)
        if x == 60:
            if contract.caller.gameOver() == True:
                break
            else:
                x=0
        x+=1
        transfer = getTransfer(1, filter,fromblock)[0]


def referral():
    fromblock = 0
    referral = getReferrals(0,0,fromblock)
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    filter = referral[1]
    referral = referral[0]
    end =0
    x = 0
    while 1:
        if len(referral) > 0:
            conn = sqlite3.connect('PurgeGame.db')
            cur = conn.cursor()
        if len(referral) > 9500:
            end = referral[9500]['blockNumber']
        c= 0
        while c < len(referral):
            if referral[c]['blockNumber']-1 == end:
                fromblock = end-1
                referral = getReferrals(0,0,fromblock)
                if len(referral) > 9500:
                    end = referral[9500]['blockNumber']
                c=0
            else:
                referrer = referral[c]['args']['referrer']
                referralCode = referral[c]['args']['referralCode']
                referee = referral[c]['args']['from']
                number = referral[c]['args']['number']
                cur.execute("INSERT INTO referrals VALUES(:address,:referralcode,:referee,:number)",
                    {'address':referrer,'referralcode':referralCode,'referee':referee,'number':number})
            c+=1
        conn.commit() 
        conn.close
        time.sleep(120)
        if x == 15:
            if contract.caller.REVEAL() == True:
                break
            else:
                x=0
        x+=1
        referral = getReferrals(1, filter,fromblock)[0]
referral()
# importmint()
# importmap()
# countTraits()
# mapPurge()

# transfer()