import csv
import discord
import sqlite3
import os,time
traitmap = 'Traitmap.csv'
categories = ["crypto", "letters", "symbols","numbers"]
rarity = ["common","common","common","","","","","",""]

intents = discord.Intents.default()
intents.members =True
client = discord.Client(intents=intents)

GUILD = "Purge Game"

@client.event
async def on_ready():
    for guild in client.guilds:
        if guild.name == GUILD:
            myguild = guild
            break
    with open(traitmap,'r') as traitmapcsvfile:
        traitmapcsvreader = csv.reader(traitmapcsvfile)
        colors = next(traitmapcsvreader)
        for y in range(0,4):
            symbols = next(traitmapcsvreader)
            for c in range(0,8):
                categorystring = categories[y] + " " + rarity[c]
                if c == 0 or c == 3:
                    category = await guild.create_category('"' +categorystring+ '"')
                traitColor = colors[c]
                for x in range(0,8):
                    traitSymbol = symbols[x]
                    conn = sqlite3.connect('PurgeGame.db')
                    cur = conn.cursor()
                    cur.execute("""
                        SELECT discordrole
                        FROM traits
                        WHERE color = ? and shape = ?
                    """,(traitColor,traitSymbol))
                    role = cur.fetchone()
                    role = guild.get_role(int(role[0]))
                    trait = traitColor + " " + traitSymbol
                    print(role.id,role.name)
                    moderator = guild.get_role(929152763978473504)
                    overwrites = {
                        role:discord.PermissionOverwrite(read_messages=True,send_messages=True),
                        moderator:discord.PermissionOverwrite(read_messages=True,send_messages=True),
                        guild.default_role:discord.PermissionOverwrite(view_channel=False)
                    }
                    await guild.create_text_channel('"' + trait + '"', category= category , overwrites = overwrites)
                    # if y == 3 and (c == 0 or c == 1 or c == 2):

                    #     scriptfile.write("configure permissions for " + '"common ' + traitSymbol + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
                    # else:
                    #     scriptfile.write("configure permissions for " + '"' + trait + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
                


# with open(traitmap,'r') as traitmapcsvfile:
#     traitmapcsvreader = csv.reader(traitmapcsvfile)
#     colors = next(traitmapcsvreader)
#     scriptfile = open("script.ds","a")
#     for y in range(0,4):
#         symbols = next(traitmapcsvreader)
#         for c in range(0,8):
#             category = categories[y] + " " + rarity[c]
#             if c == 0 or c == 3:
#                 scriptfile.write("create category " + '"' + category + '"' + "\n")
#             traitColor = colors[c]
#             for x in range(0,8):
#                 traitSymbol = symbols[x]
#                 print(traitSymbol)
#                 trait = traitColor + " " + traitSymbol
#                 channel = trait.replace(" ", "-")
#                 scriptfile.write("create text channel " + '"' + trait + '" ' + "category " + '"' + category + '"' + "\n")
#                 if y == 3 and (c == 0 or c == 1 or c == 2):
#                     scriptfile.write("configure permissions for " + '"common ' + traitSymbol + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
#                 else:
#                     scriptfile.write("configure permissions for " + '"' + trait + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
                



token = os.environ.get("DISCORD_BOT_SECRET")
client.run(token)