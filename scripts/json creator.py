import json, sqlite3


ifps = 'ipfs://QmUm7esbwi1MKAeB7qcYkSWTC7p5wWCyZTTFCUNGRMhbcH/'
conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId,trait1,trait2,trait3,trait4
    FROM tokens
    WHERE tokenId < 30000""")
tokens = cur.fetchall()
cur.execute("""
    SELECT MAX(tokenId)
    FROM tokens
    WHERE tokenId < 30000""")
tokensMinted = cur.fetchone()[0]


for row in tokens:
    tokenTraits = []
    tokenTraits.append(row[0])
    for c in range(1,5):
        cur.execute("""
        SELECT color,shape
        FROM traits
        WHERE trait =?""",(row[c],))
        trait = cur.fetchone()
        trait = trait[0] + " " + trait[1]
        tokenTraits.append(trait)

    tokenId = int(tokenTraits[0])
    tokenName = 'Purge Game Season One # ' + str(tokenId)
    image = ifps + str(tokenId) + '.png'
    data = {
        'name': tokenName,
        'description': 'Purge Game token',
        'image' : image,
        'attributes': [
        {
            'trait_type': 'Crypto', 'value': tokenTraits[1]
        },
        {
            'trait_type': 'Letter', 'value': tokenTraits[2]
        },
        {
            'trait_type': 'Symbol', 'value': tokenTraits[3]
        },
        {
            'trait_type': 'Number', 'value': tokenTraits[4]
        }
        ]
        }
    json_string = json.dumps(data)
    outputfile = "json\\"+str(tokenId)
    with open(outputfile, "w") as outfile:
        outfile.write(json_string)

for c in range(1,501):
    tokenId = 64500+c
    tokenName = 'Purge Game Bomb Token # ' + str(tokenId)
    image = ifps + 'bomb.png'
    data = {
        'name': tokenName,
        'description': 'Purge Game Bomb Token',
        'image' : image,
        'attributes': [
        {
            'trait_type': 'Bomb', 'value': 'Bomb'
        }
        ]
    }
    json_string = json.dumps(data)
    outputfile = "json\\"+str(tokenId)
    with open(outputfile, "w") as outfile:
        outfile.write(json_string)