import json, sqlite3


ifps = 'ipfs://QmNsTmdsA5JH9ACJKMnREdA8NYvs1mZAWfcMS2N8BS1w7A/'
conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId,trait1,trait2,trait3,trait4
    FROM tokens
    WHERE tokenId < 40000""")
tokens = cur.fetchall()

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
    print (outputfile)
    with open(outputfile, "w") as outfile:
        outfile.write(json_string)