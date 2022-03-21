from fastapi import FastAPI
import sqlite3
import json
from pydantic import BaseModel
app = FastAPI()
class Item(BaseModel):
    discord:int
    address:str

@app.get("/alltraits/")
async def alltraits():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM traits""")
    traitinfo = cur.fetchall()
    conn.close
    traitdata = {}
    for row in traitinfo:
        traitId = row[0]
        color = row[1]
        shape = row[2]
        total = row[3]
        traitremaining = row[4]
        image = row[5]
        traitdata[traitId] = {}
        traitdata[traitId]['traitId'] = traitId
        traitdata[traitId]['color'] = color
        traitdata[traitId]["shape"] = shape
        traitdata[traitId]["total"] = total
        traitdata[traitId]["remaining"] = traitremaining
        traitdata[traitId]["image"] = image
    return traitdata



@app.get("/tokens/{tokenId}")
async def tokens(tokenId: int):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM tokens
    WHERE tokenId = ?""",(tokenId,))
    tokeninfo = cur.fetchone()
    traitNumber = []
    for c in range(1,5):
        traitNumber.append(tokeninfo[c])
    traitName = []
    for c in range(0,4):
        cur.execute("""
        SELECT color, shape
        FROM traits
        WHERE trait = ?""",(traitNumber[c],))
        trait = cur.fetchone()
        traitName.append(trait[0] + ' ' + trait[1])
    holderaddress = tokeninfo[5]
    purgeaddress = tokeninfo[6]
    purgetime = tokeninfo[7]
    image = tokeninfo[11]
    conn.close
    return{'traitnumbers': traitNumber, 'traitnames': traitName,'holderaddress':holderaddress,'purgeaddress':purgeaddress,'purgetime': purgetime,'image':image, }

@app.get("/tokenOwner/{address}")
async def tokens(address: str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM tokens
    WHERE holderaddress = ? or purgeaddress = ?""",(address,address))
    tokeninfo = cur.fetchall()
    tokendata = {}
    for row in tokeninfo:
        traitNumber = []
        for c in range(1,5):
            traitNumber.append(row[c])
        traitName = []
        for c in range(0,4):
            cur.execute("""
            SELECT color, shape
            FROM traits
            WHERE trait = ?""",(traitNumber[c],))
            trait = cur.fetchone()
            traitName.append(trait[0] + ' ' + trait[1])
        conn.close
        holderaddress = row[5]
        purgeaddress = row[6]
        purgetime = row[7]
        image = row[12]
        tokenId = row[0]
        tokendata[tokenId] = {}
        tokendata[tokenId]['tokenId'] = tokenId
        tokendata[tokenId]['traitnumbers'] = traitNumber
        tokendata[tokenId]['traitnames'] = traitName
        tokendata[tokenId]['holderaddress'] = holderaddress
        tokendata[tokenId]['purgeaddress'] = purgeaddress
        tokendata[tokenId]['purgetime'] = purgetime
        tokendata[tokenId]['image'] = image        
    return tokendata


@app.get("/referrals/{address}")
async def referrals(address:str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT SUM(number)
    FROM referrals
    WHERE address = ?""",(address,))
    totalreferrals = cur.fetchone()
    cur.execute("""
    SELECT DISTINCT referralcode
    FROM referrals
    WHERE address = ?""",(address,))
    codes = cur.fetchall()
    codeinfo = []
    for row in codes:
        cur.execute("""
        SELECT SUM(number)
        FROM referrals
        WHERE referralcode = ?""",(row[0],))
        codesum  = cur.fetchone()[0]
        codeinfo.append([row[0], codesum])
    cur.execute("""
    SELECT DISTINCT referee
    FROM referrals
    WHERE address = ?""",(address,))
    referee = cur.fetchall()
    refereeinfo = []
    for row in referee:
        cur.execute("""
        SELECT SUM(number)
        FROM referrals
        WHERE referee = ?""",(row[0],))
        refereesum  = cur.fetchone()[0]
        refereeinfo.append([row[0], refereesum])
    conn.close
    return{'totalreferrals':totalreferrals, 'codes':codeinfo, 'referrals':refereeinfo}

@app.post("/discord/")
async def tokens(item: Item):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    INSERT OR REPLACE discord
    SET address = ?
    SET discord = ?"""),(item.address,item.discord)
    conn.commit
    conn.close
