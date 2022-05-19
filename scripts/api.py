
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import sqlite3, os
from web3 import Web3
from eth_account.messages import defunct_hash_message
from dotenv import load_dotenv
load_dotenv()
address = os.environ.get("ADDRESS")
ALCHEMY_API = os.environ.get("ALCHEMY_API")
alchemy_url = 'https://eth-rinkeby.alchemyapi.io/v2/'+ALCHEMY_API
web3 = Web3(Web3.HTTPProvider(alchemy_url))
app = FastAPI()

origins = [
    "https://purge.game",
    "http://purge.game",
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
    discriminator:str
    address:str
    username:str
    signature:str

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
    status = discordstatus(address)
    everything[4] = await status
    return everything

@app.get("/discordstatus/{address}")
async def discordstatus(address: str):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
    SELECT username
    FROM discord
    WHERE address = ?
    """,(address,))
    status = cur.fetchone()
    if status != None: return{1}
    else: return {0}

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
        winningtrait = row[7]
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
        if traitId < 64:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait1 =? AND holderaddress = ?""",(traitId,address))
        elif traitId < 128:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait2 =? AND holderaddress = ?""",(traitId,address))
        elif traitId < 192:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait3 =? AND holderaddress = ?""",(traitId,address))
        elif traitId < 256:
            cur.execute("""
            SELECT COUNT (tokenId)
            FROM tokens
            WHERE trait4 =? AND holderaddress = ?""",(traitId,address))     
        heldByAddress = cur.fetchone()[0]  
        cur.execute("""
        SELECT total 
        FROM prizepool""")
        prizepool = cur.fetchone()[0]
        traitdata[traitId] = {}
        traitdata[traitId]['traitId'] = traitId
        traitdata[traitId]['color'] = color
        traitdata[traitId]["shape"] = shape
        traitdata[traitId]["total"] = total
        traitdata[traitId]["remaining"] = traitremaining
        traitdata[traitId]["image"] = image
        traitdata[traitId]['purgedByAddress'] = purgedByAddress
        traitdata[traitId]['heldByAddress'] = heldByAddress
        traitdata[traitId]['prize'] = round( (9 / 10) * (purgedByAddress / (total-1)) * prizepool,4)
        traitdata[traitId]['floor'] = floor
        traitdata[traitId]['winningtrait'] = winningtrait
    conn.close()
    return traitdata

@app.get("/winner/{address}/{winningtrait}")
async def winner(address : str, winningtrait : int):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    if winningtrait < 64:
        cur.execute("""
        SELECT COUNT (tokenId)
        FROM tokens
        WHERE trait1 =? AND purgeaddress = ? AND trait1purge = 1""",(winningtrait,address))
    elif winningtrait < 128:
        cur.execute("""
        SELECT COUNT (tokenId)
        FROM tokens
        WHERE trait2 =? AND purgeaddress = ? AND trait2purge = 1""",(winningtrait,address))
    elif winningtrait < 192:
        cur.execute("""
        SELECT COUNT (tokenId)
        FROM tokens
        WHERE trait3 =? AND purgeaddress = ? AND trait3purge = 1""",(winningtrait,address))
    elif winningtrait < 256:
        cur.execute("""
        SELECT COUNT (tokenId)
        FROM tokens
        WHERE trait4 =? AND purgeaddress = ? AND trait3purge = 1""",(winningtrait,address))     
    winner = cur.fetchone()[0]  
    return winner


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
    conn.close()
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
    conn.close()     
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
    conn.close()   
    return tokendata

@app.get("/leaderboard")
async def leaderboard(youraddress = 0):
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
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
        if leaders[c][0] == youraddress: leaders[c] = '** YOU **'
        elif x == None:
            leaders[c] = leaders[c][0][0:6] + "..." + leaders[c][0][-5:]
        else: leaders[c] = x[0]
    if len(leaders) < 10:
        for c in range(len(leaders)+1,11):
            leaders.append('0x' + str(c))
    conn.close()
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
    conn.close()
    leaders = await lb
    leaders = leaders['leaders']
    return{'totalreferrals':totalreferrals, 'codes':codeinfo, 'referrals':refereeinfo,'leaders':leaders}

@app.post("/discord/")
async def discord(item: Item):
    original_message = '"Sign to verify address ownership"'
    message_hash = defunct_hash_message(text=original_message)
    signer = web3.eth.account.recoverHash(message_hash, signature = item.signature)
    if signer == item.address:
        conn = sqlite3.connect('PurgeGame.db')
        cur = conn.cursor()
        cur.execute("INSERT OR REPLACE INTO discord VALUES(:address, :id, :username, :discriminator)",
        {'address':item.address,'id':0,'username':item.username,'discriminator':item.discriminator})
        conn.commit()
        conn.close()

