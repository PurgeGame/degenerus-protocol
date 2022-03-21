from fileinput import close
import discord
import sqlite3,csv
import os,time

intents = discord.Intents.default()
intents.members =True
client = discord.Client(intents=intents)

GUILD = "Purge Game"
@client.event
async def on_ready():
    print('We have logged in as {0.user}'.format(client))

@client.event
async def on_ready():
    while 1:
        conn = sqlite3.connect('PurgeGame.db')
        cur = conn.cursor()
        cur.execute("""
            SELECT discord
            FROM addresses
            WHERE discord > 0""")
        discordid = cur.fetchall()
        conn.close
        for row in discordid:
            print(row[0])
            await updateroles(row[0])

    

async def updateroles(userid):
    for guild in client.guilds:
        if guild.name == GUILD:
            myguild = guild
            break
    member = myguild.get_member(int(userid))
    conn = sqlite3.connect('PurgeGame.db')
    cur = conn.cursor()
    cur.execute("""
        SELECT address
        FROM addresses
        WHERE discord = ?""",(userid,))
    address = cur.fetchone()

    cur.execute("""
        SELECT trait1,trait2,trait3,trait4
        FROM tokens
        WHERE holderaddress = ?""",(address[0],))
    traits = cur.fetchall()
    print (traits)
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
        newroles.append(myguild.get_role(roleid[0]))
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
            if currentroles[c].position <241 and currentroles[c].position != 0:
                removeroles.append(currentroles[c])

            
    print(member.name)
    for c in range(0,len(removeroles)):
        print("removing " + str(removeroles[c].name +" from " + member.name))
        await member.remove_roles(removeroles[c])

    for c in range(0,len(addroles)):
        print("adding " + str(addroles[c].name+" to " + member.name))
        await member.add_roles(addroles[c])
    print("done")
    conn.commit
    conn.close
    time.sleep(1)




token = os.environ.get("DISCORD_BOT_SECRET")
client.run(token)