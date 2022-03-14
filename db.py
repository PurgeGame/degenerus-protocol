from json.tool import main
from lib2to3.pgen2 import token
import sqlite3,csv
import discord

conn = sqlite3.connect('PurgeGame.db')
mintcsv = 'Mint.csv'
mapcsv = 'MintandPurge.csv'
purgecsv = "Purge.csv"
refercsv = "Referrals.csv"
cur = conn.cursor()


def importmint():
    with open(mintcsv,'r') as mintcsvfile:
        mintcsvreader = csv.reader(mintcsvfile)
        for row in mintcsvreader:  
            tokenTraits = row
            cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
            {'tokenId':int(tokenTraits[0]), 'trait1':int(tokenTraits[1]), 'trait2':int(tokenTraits[2]),'trait3':int(tokenTraits[3]),'trait4': int(tokenTraits[4]),
            'holderaddress':0,'purgeaddress':0,'purgetime':0,'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/' + tokenTraits[0] +'.png'})
    conn.commit()

def importmap():
    with open(mapcsv,'r') as mapcsvfile:
        mapcsvreader = csv.reader(mapcsvfile)
        for row in mapcsvreader:  
            tokenTraits = row
            cur.execute ("INSERT INTO tokens VALUES (:tokenId,:trait1,:trait2,:trait3,:trait4,:holderaddress,:purgeaddress, :purgetime, :trait1purge,:trait2purge,:trait3purge,:trait4purge,:image)", 
            {'tokenId':int(tokenTraits[0]), 'trait1':int(tokenTraits[1]), 'trait2':int(tokenTraits[2]),'trait3':int(tokenTraits[3]),'trait4': int(tokenTraits[4]),
            'holderaddress':0,'purgeaddress':tokenTraits[5],'purgetime':int(tokenTraits[6]),'trait1purge':0,'trait2purge':0,'trait3purge':0,'trait4purge':0,'image':'https://purge.game/img/tokens/' + tokenTraits[0] +'.png'})
    conn.commit()  

def countTraits():
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

def removetraits(_tokenId):
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

def mapPurge():
    with open(mapcsv,'r') as mapcsvfile:
        mapcsvreader = csv.reader(mapcsvfile)
        mapcsvfile.seek(0)
        for row in mapcsvreader:  
            tokenTraits = row
            removetraits(tokenTraits[0])

def transfer():
    with open(purgecsv,'r') as purgecsvfile:
        purgecsvreader = csv.reader(purgecsvfile)
        purgecsvfile.seek(0)
        for row in purgecsvreader:  
            transfer = row
            if int(transfer[0]) < 65001:
                if transfer[2] == '0x0000000000000000000000000000000000000000':
                    cur.execute(
                        """UPDATE tokens SET purgetime = ?, purgeaddress = ?, holderaddress = 0
                        WHERE tokenId = ?""",(transfer[3],transfer[1],transfer[0]))
                    removetraits(transfer[0])
                else:
                    cur.execute(
                        """UPDATE tokens SET holderaddress = ?
                        WHERE tokenId = ?""",(transfer[2],transfer[0]))
        conn.commit()

def referral():
    with open(refercsv,'r') as refercsvfile:
        refercsvreader = csv.reader(refercsvfile)
        for row in refercsvreader:  
            refer = row
            cur.execute("""
                SELECT * 
                FROM addresses 
                WHERE address = ?""",(refer[0],))
            if cur.fetchone() is None:
                cur.execute("INSERT INTO addresses VALUES(:address,:discord,:referrals)",
                {'address':refer[0],'discord':0,'referrals':refer[1]})
            else:
                cur.execute("""UPDATE addresses SET referrals = referrals + ?
                        WHERE address = ?""",(refer[1],refer[0]))


    conn.commit() 



importmint()
importmap()
countTraits()
mapPurge()
transfer()
referral()
print("done")
       



conn.close