import sqlite3,urllib.request
import json, time
from web3 import Web3
import os

address = os.environ.get("ADDRESS")

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
creation = contract.events.OwnershipTransferred()
creFilter = creation.createFilter(fromBlock = 0)
cre = creFilter.get_all_entries()
startblock = cre[0]['blockNumber']

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
        if fromblock > web3.eth.block_number: time.sleep(120)
        filter = Transfer.createFilter(fromBlock = fromblock)
        referrals = filter.get_all_entries()
    else:
        referrals = filter.get_new_entries()
    return(referrals, filter)

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

# def getReferrals(new, filter,fromblock):
#     Referred = contract.events.Referred()
#     if new == 0:
#         conn = sqlite3.connect('PurgeGame.db')
#         cur = conn.cursor()
#         cur.execute('DROP TABLE IF EXISTS referrals')
#         cur.execute("""CREATE TABLE referrals (
#         address TEXT,
#         referralcode TEXT,
#         referee TEXT,
#         number INTEGER
#         )""")
#         conn.commit
#         conn.close
#         filter = Referred.createFilter(fromBlock = fromblock)
#         ref = filter.get_all_entries()
#     else:
#         filter = Referred.createFilter(fromBlock = fromblock)
#         ref = filter.get_all_entries()
#     return(ref, filter)

# def referral():
#     fromblock = 0
#     referral = getReferrals(0,0,fromblock)
#     conn = sqlite3.connect('PurgeGame.db')
#     cur = conn.cursor()
#     filter = referral[1]
#     referral = referral[0]
#     end = 0
#     x = 15
#     while 1:
#         if len(referral) > 0:
#             conn = sqlite3.connect('PurgeGame.db')
#             cur = conn.cursor()
#         if len(referral) > 9000:
#             end = referral[9000]['blockNumber']
#         c = 0
#         while c < len(referral):
#             if referral[c]['blockNumber']-1 == end:
#                 fromblock = end +1
#                 referral = getReferrals(1,filter,fromblock)[0]
#                 if len(referral) > 9000:
#                     end = referral[9000]['blockNumber']
#                 c = 0
#             else:
#                 referrer = referral[c]['args']['referrer']
#                 referralCode = referral[c]['args']['referralCode']
#                 referee = referral[c]['args']['from']
#                 number = referral[c]['args']['number']
#                 cur.execute("INSERT INTO referrals VALUES(:address,:referralcode,:referee,:number)",
#                     {'address':referrer,'referralcode':referralCode,'referee':referee,'number':number})
#                 fromblock = referral[c]['blockNumber'] +1
#             c += 1
#         conn.commit() 
#         conn.close
#         time.sleep(60)
#         if x == 15:
#             if contract.caller.REVEAL() == True:
#                 break
#             else:
#                 x = 0
#         x += 1
#         referral = getReferrals(1, filter,fromblock)[0]

referral()
print('done')