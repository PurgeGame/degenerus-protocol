from json.tool import main
from lib2to3.pgen2 import token
import sqlite3,csv
import discord,sys
import os
client = discord.Client()
traitmap = 'traitmap.csv'
conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()



cur.execute("""CREATE TABLE traits (
    trait INTEGER,
    color TEXT,
    shape TEXT,
    total INTEGER,
    remaining INTEGER,
    image TEXT,
    discordrole INTEGER,
    PRIMARY KEY(trait)
    )""")

cur.execute("""CREATE TABLE tokens (
    tokenId INTEGER,
    trait1 INTEGER,
    trait2 INTEGER,
    trait3 INTEGER,
    trait4 INTEGER,
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


cur.execute("""CREATE TABLE addresses (
    address TEXT,
    discord TEXT,
    referrals INTEGER,
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
                traitimage = 'https://purge.game/img/traits/' + color + "_" + shape +'.png'
                traitimage = traitimage.lower()
                cur.execute("INSERT INTO traits VALUES(:trait,:color,:shape,:remaining,:total,:image,:discordrole)",{'trait':trait,'color':color,'shape':shape,'remaining':0,'total':0,'image': traitimage,'discordrole':0})
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
        for x in range(1,242):
            rolename = str(roles[x])
            if rolename == traitstring:
                cur.execute(
                    """UPDATE traits 
                    SET discordrole = ?
                    WHERE trait = ?""",(roles[x].id,c))
        
    conn.commit()
    conn.close
    print("done")

    



token = os.environ.get("DISCORD_BOT_SECRET")
client.run(token)
