import sqlite3,urllib.request
import json, time
from web3 import Web3
import os


offset = 420

address = os.environ.get("ADDRESS")
ALCHEMY_API = os.environ.get("ALCHEMY_API")
ETHERSCAN_API_ONE = os.environ.get("ETHERSCAN_API_ONE")

alchemy_url = 'https://eth-rinkeby.alchemyapi.io/v2/'+ALCHEMY_API
web3 = Web3(Web3.HTTPProvider(alchemy_url))
null = None

ESAPI = 'https://api-rinkeby.etherscan.io/api?module=contract&action=getabi&address=' + address + '&apikey=' + ETHERSCAN_API_ONE
with urllib.request.urlopen(ESAPI) as url:
    data = url.read().decode()
    contractabi = json.loads(data)['result']

address = Web3.toChecksumAddress(address)
contract = web3.eth.contract(address= address, abi=contractabi)
creation = contract.events.OwnershipTransferred()
creFilter = creation.createFilter(fromBlock = 0)

cre = creFilter.get_all_entries()
startblock = cre[0]['blockNumber']





def purgetime(block):
    # purgeTime = web3.eth.getblock(block)
    # purgeTime = purgeTime['timestamp']
    purgeTime = int(time.time())
    return (purgeTime)

def getTransferAll():
    Transfer = contract.events.Transfer()
    Transfers = []
    currentblock = web3.eth.block_number
    fromblock = startblock
    while fromblock <= currentblock:
        toblock = min(fromblock + 1999, currentblock)
        filter = Transfer.createFilter(fromBlock = fromblock, toBlock = toblock)
        Transfers += filter.get_all_entries()
        fromblock = toblock+1
    return (Transfers)

def getTransferNew(fromblock, filter):
    Transfer = contract.events.Transfer()
    if filter == 0:
        filter = Transfer.createFilter(fromBlock = fromblock)
        Transfers = filter.get_all_entries()
    else:
        Transfers = filter.get_new_entries()
    return(Transfers, filter)

def getMAP():
    MintAndPurge = contract.events.MintAndPurge()
    MintAndPurges = []
    currentblock = web3.eth.block_number
    fromblock = startblock
    while fromblock <= currentblock:
        toblock = min(fromblock + 1999, currentblock)
        filter = MintAndPurge.createFilter(fromBlock = fromblock, toBlock = toblock)
        MintAndPurges += filter.get_all_entries()
        fromblock = toblock+1
    return (MintAndPurges)

def getMints():
    TokenMinted = contract.events.TokenMinted()
    mints = []
    currentblock = web3.eth.block_number
    fromblock = startblock
    while fromblock <= currentblock:
        toblock = min(fromblock + 1999, currentblock)
        filter = TokenMinted.createFilter(fromBlock = fromblock, toBlock = toblock)
        mints += filter.get_all_entries()
        fromblock = toblock+1
    return(mints)

def getReferralsAll():
    Referred = contract.events.Referred()
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
    currentblock = web3.eth.block_number
    fromblock = startblock
    referrals = []
    while fromblock <= currentblock:
        toblock = min(fromblock + 1999, currentblock)
        filter = Referred.createFilter(fromBlock = fromblock, toBlock = toblock)
        referrals += filter.get_all_entries()
        fromblock = toblock+1
    return (referrals)


def getReferralsNew(fromblock, filter):
    Transfer = contract.events.Referred()
    if filter == 0:
        filter = Transfer.createFilter(fromBlock = fromblock)
        referrals = filter.get_all_entries()
    else:
        referrals = filter.get_new_entries()
    return(referrals, filter)

def importmint():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    mints = getMints()
    totalMints = contract.caller.totalMinted()
    cur.execute("""
        SELECT COUNT(tokenId)
        FROM tokens
        WHERE tokenId > 64500 """)
    bombcount = cur.fetchone()[0]
    totalMints-= bombcount
    c=0
    while c < len(mints):
        tokenTraits = mints[c]['args']['tokenTraits']
        tokenTraitOne = tokenTraits & 0x3f
        tokenTraitTwo = ((tokenTraits & 0xfc0) >> 6) + 64
        tokenTraitThree = ((tokenTraits & 0x3f000) >> 12) + 128
        tokenTraitFour = ((tokenTraits & 0xfc0000) >> 18) + 192
        tokenId = mints[c]['args']['tokenId']
        if tokenId < 64501:
            if tokenId-offset < 1 :
                realtokenId = totalMints - (offset - tokenId)
            else:
                realtokenId = tokenId - offset
            holder = mints[c]['args']['from']
            tokenData = [str(realtokenId),tokenTraitOne,tokenTraitTwo,tokenTraitThree,tokenTraitFour]
            cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:price,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
            {'tokenId':int(tokenData[0]), 'trait1':int(tokenData[1]), 'trait2':int(tokenData[2]),'trait3':int(tokenData[3]),'trait4': int(tokenData[4]),'price': null,
            'holderaddress':holder,'purgeaddress':0,'purgetime':0,'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/' + tokenData[0] +'.png'})
        c+=1
    conn.commit()
    conn.close

def importmap():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    MintAndPurges = getMAP()
    c =0
    while c< len(MintAndPurges):
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
        cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:price,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
        {'tokenId':int(tokenData[0]), 'trait1':int(tokenData[1]), 'trait2':int(tokenData[2]),'trait3':int(tokenData[3]),'trait4': int(tokenData[4]),'price': null,
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
    cur.execute("""
        SELECT COUNT(trait1)
        FROM tokens
        WHERE trait1 = 256""")
    traitcount = cur.fetchone()
    cur.execute(
        """UPDATE traits SET total = ?, remaining = ?
        WHERE trait = ?""",(traitcount[0],traitcount[0],256))
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
        if _trait != 256 or c == 1:
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
    transfer = getTransferAll()
    filter = 0
    x=60
    while 1:
        if len(transfer) > 0:
            conn = sqlite3.connect('PurgeGame.db')
            cur = conn.cursor()
        c=0
        while c< len(transfer):
            tokenId = transfer[c]['args']['tokenId']
            cur.execute("""
            SELECT * 
            FROM tokens 
            WHERE tokenId = ?""",(tokenId,))
            token = cur.fetchone()
            if token == None:
                cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:price,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
                {'tokenId':tokenId, 'trait1':256, 'trait2':256,'trait3':256,'trait4': 256,'price':null,'holderaddress':0,'purgeaddress':0,'purgetime':0,'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/bomb.png'})
                cur.execute("UPDATE traits SET total =total + 1, remaining = remaining +1 WHERE trait = 256")
                conn.commit()
            if transfer[c]['args']['to'] == '0x0000000000000000000000000000000000000000':
                block = transfer[c]['blockNumber']

                purgeTime = purgetime(block)
                if token[8] ==0:
                    cur.execute(
                        """UPDATE tokens SET purgetime = ?, purgeaddress = ?, holderaddress = 0, price = ?
                        WHERE tokenId = ?""",(purgeTime,transfer[c]['args']['from'],null,tokenId))
                    removetraits(transfer[c]['args']['tokenId'],conn)
            else:
                cur.execute(
                    """UPDATE tokens SET holderaddress = ?
                    WHERE tokenId = ?""",(transfer[c]['args']['to'],tokenId))
            fromblock = transfer[c]['blockNumber'] +1
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
        transfer = getTransferNew(fromblock, filter)
        filter = transfer[1]
        transfer = transfer[0]

def prizepool():
    eth = 1000000000000000000
    prizepool = contract.caller.PrizePool() / eth
    cost = contract.caller.cost() / eth
    print(prizepool,cost)
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
        SELECT COUNT(tokenId)
        FROM tokens
        WHERE tokenId >30000 AND tokenId < 64421
        """)
    mapTokens = int(cur.fetchone()[0])
    mapJackpot = mapTokens * cost / 20
    remaining = prizepool - mapJackpot
    grandPrize = prizepool / 10 - mapJackpot
    print(mapTokens,mapJackpot,remaining,grandPrize)
    cur.execute("INSERT INTO prizepool VALUES(:total, :grandprize, :mapjackpot, :remaining)",
    {'total':prizepool,'grandprize':grandPrize,'mapjackpot':mapJackpot,'remaining':remaining})
    conn.commit()
    conn.close

def referral():
    filter = 0
    referral = getReferralsAll()
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    x = 15
    while 1:
        if len(referral) > 0:
            conn = sqlite3.connect('PurgeGame.db')
            cur = conn.cursor()
        c= 0
        while c < len(referral):
            referrer = referral[c]['args']['referrer']
            referralCode = referral[c]['args']['referralCode']
            referee = referral[c]['args']['from']
            number = referral[c]['args']['number']
            cur.execute("INSERT INTO referrals VALUES(:address,:referralcode,:referee,:number)",
                {'address':referrer,'referralcode':referralCode,'referee':referee,'number':number})
            fromblock = referral[c]['blockNumber'] +1
            c+=1
        conn.commit() 
        conn.close
        time.sleep(30)
        if x == 15:
            if contract.caller.REVEAL() == True:
                break
            else:
                x=0
        x+=1
        referral = getReferralsNew(fromblock,filter)
        filter = referral[1]
        referral = referral[0]
# referral()
importmint()
importmap()
countTraits()
mapPurge()
prizepool()
print('done')
transfer()