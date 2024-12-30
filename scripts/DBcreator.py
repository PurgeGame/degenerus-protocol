import sqlite3,csv
import discord
import os
from dotenv import load_dotenv
load_dotenv()
token = os.environ.get("DISCORD_BOT_SECRET")
client = discord.Client()
traitmap = 'traitmap.csv'
null = None
conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()

cur.execute('DROP TABLE IF EXISTS tokens')
cur.execute('DROP TABLE IF EXISTS traits')
cur.execute('DROP TABLE IF EXISTS discord')
cur.execute('DROP TABLE IF EXISTS referrals')
cur.execute('DROP TABLE IF EXISTS prizepool')
cur.execute('DROP TABLE IF EXISTS leaderboard')



cur.execute("""CREATE TABLE traits (
    trait INTEGER,
    color TEXT,
    shape TEXT,
    total INTEGER,
    remaining INTEGER,
    floor REAL,
    image TEXT,
    winningtrait INTEGER,
    discordrole INTEGER,
    PRIMARY KEY(trait)
    )""")

cur.execute("""CREATE TABLE tokens (
    tokenId INTEGER,
    trait1 INTEGER,
    trait2 INTEGER,
    trait3 INTEGER,
    trait4 INTEGER,
    price REAL,
    holderaddress TEXT,
    purgeaddress TEXT,
    purgetime INTEGER,
    trait1purge INTEGER,
    trait2purge INTEGER,
    trait3purge INTEGER,
    trait4purge INTEGER,
    image TEXT,
    PRIMARY KEY(tokenId),
    FOREIGN KEY (trait1) REFERENCES traits(trait),
    FOREIGN KEY (trait2) REFERENCES traits(trait),
    FOREIGN KEY (trait3) REFERENCES traits(trait),
    FOREIGN KEY (trait4) REFERENCES traits(trait)
    )""")


cur.execute("""CREATE TABLE discord (
    address TEXT,
    id TEXT,
    username TEXT,
    discriminator TEXT,
    PRIMARY KEY(address)
    )""")

cur.execute("""CREATE TABLE referrals (
    address TEXT,
    referralcode TEXT,
    referee TEXT,
    number INTEGER
    )""")

cur.execute("""CREATE TABLE prizepool (
    total REAL,
    grandprize REAL,
    mapjackpot REAL,
    remaining REAL
    )""")

cur.execute("""CREATE TABLE leaderboard (
    address TEXT,
    total INTEGER,
    PRIMARY KEY(address)
    )""")

with open(traitmap,'r') as traitmapcsvfile:
    traitmapcsvreader = csv.reader(traitmapcsvfile)
    traitColor = next(traitmapcsvreader)
    for count in range(0,4):
        traitShape = next(traitmapcsvreader)
        for c in range(0,8):
            color = traitColor[int(c)]
            for x in range(0,8):
                shape = traitShape[x]
                trait = count * 64 + c * 8 + x
                traitimage = 'https://purge.game/img/' + color + "_" + shape +'.png'
                traitimage = traitimage.lower()
                cur.execute("INSERT INTO traits VALUES(:trait,:color,:shape,:remaining,:total,:floor,:image,:winningtrait,:discordrole)",{'trait':trait,'color':color,'shape':shape,'remaining':0,'total':0,'floor': null,'image': traitimage,'winningtrait':0, 'discordrole':0})
    cur.execute("INSERT INTO traits VALUES(:trait,:color,:shape,:remaining,:total,:floor,:image,:winningtrait,:discordrole)",{'trait':256,'color':'Bomb','shape':'Token','remaining':0,'total':0,'floor':null,'image': 'https://purge.game/img/tokens/bomb.png','winningtrait':0,'discordrole':0})
    conn.commit()
    
@client.event
async def on_ready():

    GUILD = "Purge Game"
    for guild in client.guilds:
        if guild.name == GUILD:
            myguild = guild
            break
    roles = myguild.roles
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    for c in range(0,256):
        cur.execute("""
            SELECT *
            FROM traits
            WHERE trait = ?""",(c,))
        traitstring = cur.fetchone()
        if (traitstring[1] == 'Brown' or traitstring[1] == 'Pink' or traitstring[1] == 'Orange') and ((traitstring[2] == '1') or (traitstring[2] == '2')or (traitstring[2] == '3')or (traitstring[2] == '4')or (traitstring[2] == '5')or (traitstring[2] == '6')or (traitstring[2] == '7')or (traitstring[2] == '8')):
            traitstring = "Common " + traitstring[2]
        else:
            traitstring = traitstring[1] + " " + traitstring[2]
        for x in range(1,243):
            rolename = str(roles[x])
            if rolename == traitstring:
                cur.execute(
                    """UPDATE traits 
                    SET discordrole = ?
                    WHERE trait = ?""",(roles[x].id,c))
        
    conn.commit()
    conn.close
    print("done")

    




client.run(token)
