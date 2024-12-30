import sqlite3,urllib.request
import json, time
from web3 import Web3

import os
from dotenv import load_dotenv
load_dotenv()

address = os.environ.get("ADDRESS")
ALCHEMY_API = os.environ.get("ALCHEMY_API")


alchemy_url = 'https://eth-rinkeby.alchemyapi.io/v2/'+ALCHEMY_API
web3 = Web3(Web3.HTTPProvider(alchemy_url))
null = None


with open('abi.txt') as f:
    contractabi = f.read()

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
        if traitremaining == 0 and _trait != 256:
            cur.execute("""
                SELECT COUNT (trait)
                FROM traits
                WHERE winningtrait == 1""")
            if cur.fetchone()[0] == 0:
                cur.execute(
                    """UPDATE traits SET winningtrait = 1
                    WHERE trait = ?""",(_trait,))

def transfer():
    transfer = getTransferAll()
    bombs = 0
    filter = 0
    x=60
    while 1:
        if len(transfer) > 0:
            conn = sqlite3.connect('PurgeGame.db')
            cur = conn.cursor()
            c=0
            while c< len(transfer):
                tokenId = transfer[c]['args']['tokenId']
                if tokenId > 0:
                    cur.execute("""
                    SELECT * 
                    FROM tokens 
                    WHERE tokenId = ?""",(tokenId,))
                    token = cur.fetchone()
                    if token == None:
                        cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:price,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
                        {'tokenId':tokenId, 'trait1':256, 'trait2':256,'trait3':256,'trait4': 256,'price':null,'holderaddress':0,'purgeaddress':0,'purgetime':0,'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/bomb.png'})
                        cur.execute("UPDATE traits SET total =total + 1, remaining = remaining +1 WHERE trait = 256")
                    if transfer[c]['args']['to'] == '0x0000000000000000000000000000000000000000':
                        block = transfer[c]['blockNumber']

                        purgeTime = purgetime(block)
                        if token[8] ==0:
                            removetraits(transfer[c]['args']['tokenId'],conn)                       
                            cur.execute(
                                """UPDATE tokens SET purgetime = ?, purgeaddress = ?, holderaddress = 0, price = ?
                                WHERE tokenId = ?""",(purgeTime,transfer[c]['args']['from'],null,tokenId))
                    else:
                        cur.execute(
                            """UPDATE tokens SET holderaddress = ?
                            WHERE tokenId = ?""",(transfer[c]['args']['to'],tokenId))
                    fromblock = transfer[c]['blockNumber'] +1
                c+=1
            conn.commit()
            conn.close()
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
transfer()