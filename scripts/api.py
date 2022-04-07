from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import sqlite3
from pydantic import BaseModel

app = FastAPI()
origins = [
    "http://localhost:3000",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
class Item(BaseModel):
    discord:int
    address:str

@app.get("/everything/{address}")
async def everything(address: str):
    everything = {}
    everything[0] = await alltraits(address)
    everything[1] = await tokenOwner(address)
    everything[3] = await tokenPurger(address)
    everything[2] = await prizepool()
    return everything

@app.get("/alltraits/{address}")
async def alltraits(address : str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM traits
    WHERE trait < 256""")
    traitinfo = cur.fetchall()
    
    traitdata = {}
    for row in traitinfo:
        traitId = row[0]
        color = row[1]
        shape = row[2]
        total = row[3]
        traitremaining = row[4]
        image = row[5]
        if traitId < 64:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait1 =? AND purgeaddress = ?""",(traitId,address))
        elif traitId < 128:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait2 =? AND purgeaddress = ?""",(traitId,address))
        elif traitId < 192:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait3 =? AND purgeaddress = ?""",(traitId,address))
        elif traitId < 256:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait4 =? AND purgeaddress = ?""",(traitId,address))     
        purgedByAddress = cur.fetchone()[0] 
        cur.execute("""
        SELECT total 
        FROM prizepool""")
        prizepool = cur.fetchone()[0]
        conn.close
        traitdata[traitId] = {}
        traitdata[traitId]['traitId'] = traitId
        traitdata[traitId]['color'] = color
        traitdata[traitId]["shape"] = shape
        traitdata[traitId]["total"] = total
        traitdata[traitId]["remaining"] = traitremaining
        traitdata[traitId]["image"] = image
        traitdata[traitId]['purgedByAddress'] = purgedByAddress
        traitdata[traitId]['normalpayout'] = round(9 * purgedByAddress * prizepool / (total  * 10),4)
    return traitdata

@app.get("/prizepool")
async def prizepool():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM prizepool
    """)
    prizes = cur.fetchone()
    return{'total': prizes[0], 'grandprize': prizes[1], 'mapjackpot': prizes[2], 'remaining': prizes[3]}

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
async def tokenOwner(address: str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM tokens
    WHERE holderaddress = ?""",(address,))
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

@app.get("/tokenPurger/{address}")
async def tokenPurger(address: str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT *
    FROM tokens
    WHERE purgeaddress = ?""",(address,))
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
