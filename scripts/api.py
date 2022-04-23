from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3

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
    username:str

@app.get("/everything/{address}")
async def everything(address: str):
    everything = {}
    traits = alltraits(address)
    everything[0] = await traits
    owner = tokenOwner(address)
    everything[1] = await owner
    purger = tokenPurger(address)
    everything[2] = await purger
    prize = prizepool()
    everything[3] = await prize
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
        image = row[6]
        floor = row[5]
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
        traitdata[traitId]['prize'] = round(9 * purgedByAddress * prizepool / (total  * 10),4)
        traitdata[traitId]['floor'] = floor
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
    holderaddress = tokeninfo[6]
    purgeaddress = tokeninfo[7]
    purgetime = tokeninfo[8]
    image = tokeninfo[13]
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
        price = row[5]
        holderaddress = row[6]
        purgeaddress = row[7]
        purgetime = row[8]
        image = row[13]
        tokenId = row[0]
        tokendata[tokenId] = {}
        tokendata[tokenId]['tokenId'] = tokenId
        tokendata[tokenId]['traitnumbers'] = traitNumber
        tokendata[tokenId]['traitnames'] = traitName
        tokendata[tokenId]['price'] = price
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
        price = row[5]
        holderaddress = row[6]
        purgeaddress = row[7]
        purgetime = row[8]
        image = row[13]
        tokenId = row[0]
        tokendata[tokenId] = {}
        tokendata[tokenId]['tokenId'] = tokenId
        tokendata[tokenId]['traitnumbers'] = traitNumber
        tokendata[tokenId]['traitnames'] = traitName
        tokendata[tokenId]['price'] = price
        tokendata[tokenId]['holderaddress'] = holderaddress
        tokendata[tokenId]['purgeaddress'] = purgeaddress
        tokendata[tokenId]['purgetime'] = purgetime
        tokendata[tokenId]['image'] = image        
    return tokendata

@app.get("/leaderboard")
async def leaderboard(youraddress = 0):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT DISTINCT address
    FROM referrals""")
    allReferrers = cur.fetchall()
    print(allReferrers)
    for row in allReferrers:
        cur.execute("""
        SELECT SUM(number)
        FROM referrals
        WHERE address = ?""",(row[0],))
        total = cur.fetchone()
        cur.execute("INSERT INTO leaderboard VALUES(:address,:total)",{'address':row[0],'total':total[0]})
    cur.execute("""
    SELECT address
    from leaderboard
    ORDER BY total DESC""")
    leaders = cur.fetchall()
    for c in range(0,len(leaders)):
        cur.execute("""
        SELECT username
        FROM discord
        WHERE address = ?""",(leaders[c][0],))
        x = cur.fetchone()
        print(leaders[c], youraddress)
        if leaders[c][0] == youraddress: leaders[c] = '** YOU **'
        elif x == None:
            leaders[c] = leaders[c][0]
        else: leaders[c] = x[0]
    conn.close
    return{'leaders':leaders}
    



@app.get("/referrals/{address}")
async def referrals(address:str):
    lb = leaderboard(address)
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT SUM(number)
    FROM referrals
    WHERE address = ?""",(address,))
    totalreferrals = cur.fetchone()[0]
    cur.execute("""
    SELECT DISTINCT referralcode
    FROM referrals
    WHERE address = ?""",(address,))
    codes = cur.fetchall()
    codeinfo = {}
    for row in codes:
        cur.execute("""
        SELECT SUM(number)
        FROM referrals
        WHERE referralcode = ?""",(row[0],))
        codesum  = cur.fetchone()[0]
        codeinfo[row[0]] = codesum
    cur.execute("""
    SELECT DISTINCT referee
    FROM referrals
    WHERE address = ?""",(address,))
    referee = cur.fetchall()
    refereeinfo = {}
    for row in referee:
        cur.execute("""
        SELECT SUM(number)
        FROM referrals
        WHERE referee = ? AND address = ?""",(row[0],address))
        refereesum  = cur.fetchone()[0]
        refereeinfo[row[0]] = refereesum
    conn.close
    leaders = await lb
    return{'totalreferrals':totalreferrals, 'codes':codeinfo, 'referrals':refereeinfo,'leaders':leaders}

@app.post("/discord/")
async def tokens(item: Item):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    INSERT OR REPLACE discord
    SET address = ?
    SET discord = ?
    SET username = ?"""),(item.address,item.discord,item.username)
    conn.commit
    conn.close
