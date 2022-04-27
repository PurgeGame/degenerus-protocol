import discord
import sqlite3
import os,time
from dotenv import load_dotenv
load_dotenv()

intents = discord.Intents.default()
intents.members =True
client = discord.Client(intents=intents)

GUILD = "Purge Game"
@client.event
async def on_ready():
    print('We have logged in as {0.user}'.format(client))

@client.event
async def on_ready():
    c=10
    while 1:
        conn = sqlite3.connect('PurgeGame.db')
        cur = conn.cursor()
        cur.execute("""
            SELECT id
            FROM discord
            WHERE id > 0""")
        discordid = cur.fetchall()

        conn.close()
        for row in discordid:
            await updateroles(row[0])
        if c == 10:
            await updateIDs()
            c=0
        c+=1

async def updateIDs():
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    for guild in client.guilds:
        if guild.name == GUILD:
            myguild = guild
            break

    async for member in myguild.fetch_members(limit=None):
        cur.execute("""
        SELECT username,discriminator,id
        FROM discord
        WHERE username = ? and discriminator = ?""",(member.name,member.discriminator))
        _member = cur.fetchone()
        if _member != None:
            if int(_member[2]) != int(member.id):
                cur.execute("""
                    UPDATE discord SET id =?
                    WHERE username = ? AND discriminator = ?""",(member.id,member.name,member.discriminator))
                conn.commit()
    conn.close()

    

async def updateroles(userid):
    for guild in client.guilds:
        if guild.name == GUILD:
            myguild = guild
            break
    member = myguild.get_member(int(userid))

    if member != None:
        conn = sqlite3.connect('PurgeGame.db')
        cur = conn.cursor()
        cur.execute("""
            SELECT address
            FROM discord
            WHERE id = ?""",(userid,))
        address = cur.fetchone()
        cur.execute("""
            SELECT trait1,trait2,trait3,trait4
            FROM tokens
            WHERE holderaddress = ? AND trait1 != 256""",(address[0],))
        traits = cur.fetchall()
        traitarray = []
        newroles = []
        for row in traits:
            traitrow = row
            for c in range (0,4):
                traitarray.append(traitrow[c])
        for c in range(0,len(traitarray)):
            cur.execute("""
                SELECT discordrole
                FROM traits
                WHERE trait = ?""",(traitarray[c],))
            roleid = cur.fetchone()
            role = myguild.get_role(roleid[0])
            if role not in newroles:
                newroles.append(role) 
        currentroles = member.roles
        addroles = []
        removeroles = []
        for x in range(0,len(newroles)):
            match = 0
            for c in range(0,len(currentroles)):
                if currentroles[c] == newroles[x]:
                    match = 1
            if match == 0:
                addroles.append(newroles[x])
        for c in range(0,len(currentroles)):
            match = 0
            for x in range(0,len(newroles)):
                if currentroles[c] == newroles[x]:
                    match = 1
            if match == 0:
                if currentroles[c].position <242 and currentroles[c].position != 0:
                    removeroles.append(currentroles[c]) 
        for c in range(0,len(removeroles)):
            print("removing " + str(removeroles[c].name +" from " + member.name))
            await member.remove_roles(removeroles[c])
        for c in range(0,len(addroles)):
            print("adding " + str(addroles[c].name+" to " + member.name))
            await member.add_roles(addroles[c])
        conn.commit()
        conn.close()
        time.sleep(1)




token = os.environ.get("DISCORD_BOT_SECRET")
client.run(token)