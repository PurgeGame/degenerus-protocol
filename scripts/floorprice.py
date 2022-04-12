import requests
import os, time, json, sqlite3

OS_API = os.environ.get("OS_API")
address = os.environ.get("ADDRESS")
eth = 1000000000000000000

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId
    FROM tokens
    WHERE purgeaddress = 0""")
tokens = cur.fetchall()



c = 0
while c < len(tokens)-1:
    if c+28 >= len(tokens):
        c = len(tokens)-29
    offset = 0
    getmore = 1
    tokensFound = []
    while getmore == 1:
        url = "https://testnets-api.opensea.io/wyvern/v1/orders?asset_contract_address=" + address + "&bundled=false&include_bundled=false&listed_after=12454&token_ids=" +str(c)+ "&token_ids=" + str(tokens[c][0]) + "&token_ids=" + str(tokens[c+1][0]) + "&token_ids=" + str(tokens[c+2][0]) + "&token_ids=" +str(tokens[c+3][0])+ "&token_ids=" + str(tokens[c+4][0]) + "&token_ids=" +str(tokens[c+5][0]) + "&token_ids=" + str(tokens[c+6][0]) + "&token_ids=" + str(tokens[c+7][0]) + "&token_ids=" +str(tokens[c+8][0])+ "&token_ids=" + str(tokens[c+9][0]) +"&token_ids=" +str(tokens[c+10][0]) + "&token_ids=" + str(tokens[c+11][0]) + "&token_ids=" + str(tokens[c+12][0]) + "&token_ids=" +str(tokens[c+13][0])+ "&token_ids=" + str(tokens[c+14][0]) +"&token_ids=" +str(tokens[c+15][0]) + "&token_ids=" + str(tokens[c+16][0]) + "&token_ids=" + str(tokens[c+17][0]) + "&token_ids=" +str(tokens[c+18][0])+ "&token_ids=" + str(tokens[c+19][0]) +"&token_ids=" +str(tokens[c+20][0]) + "&token_ids=" + str(tokens[c+21][0]) + "&token_ids=" + str(tokens[c+22][0]) + "&token_ids=" +str(tokens[c+23][0])+ "&token_ids=" + str(tokens[c+24][0]) +"&token_ids=" +str(tokens[c+25][0]) + "&token_ids=" + str(tokens[c+26][0]) + "&token_ids=" + str(tokens[c+27][0]) + "&token_ids=" +str(tokens[c+28][0]) +"&limit=50&offset=" + str(offset) + "&order_by=created_date&order_direction=desc"

        headers = {"Accept": "application/json"}
        response = requests.request("GET", url, headers=headers)

        orders = json.loads(response.text)['orders']
        if (len(orders) == 50):
            getmore= 1
            offset+=50
        else:
            getmore = 0

        for x in range(len(orders)-1,-1,-1):
            tokenId = int(orders[x]['metadata']['asset']['id'])
            price = round(float(orders[x]['current_price']) / eth,2)
            cur.execute("""
            UPDATE tokens SET price = ?
            WHERE tokenId = ?""",(price,tokenId))
            tokensFound.append(tokenId)
        time.sleep(1)
    tokensNotFound = []
    for x in range(c,c+29):
        if tokens[x][0] not in tokensFound:
            tokensNotFound.append(tokens[x][0])
    print(tokensNotFound)

    for x in tokensNotFound:
        cur.execute("""
        UPDATE tokens SET price = NULL
        WHERE tokenId = ?""",(x,))
    c+=29

for traitId in range(0,256):
    if traitId < 64:
        cur.execute("""
        SELECT price
        FROM tokens
        WHERE price IS NOT NULL AND trait1 = ?
        ORDER BY price DESC""",(traitId,))
        price = cur.fetchone()
        if price != None:
            price = price[0]
        cur.execute("""
        UPDATE traits SET floor = ?
        WHERE trait = ?""",(price,traitId))
    elif traitId < 128:
        cur.execute("""
        SELECT price
        FROM tokens
        WHERE price IS NOT NULL AND trait2 = ?
        ORDER BY price DESC""",(traitId,))
        price = cur.fetchone()
        if price != None:
            price = price[0]
        cur.execute("""
        UPDATE traits SET floor = ?
        WHERE trait = ?""",(price,traitId))
    elif traitId < 192:
        cur.execute("""
        SELECT price
        FROM tokens
        WHERE price IS NOT NULL AND trait3 = ?
        ORDER BY price DESC""",(traitId,))
        price = cur.fetchone()
        if price != None:
            price = price[0]
        cur.execute("""
        UPDATE traits SET floor = ?
        WHERE trait = ?""",(price,traitId))
    elif traitId < 256:
        cur.execute("""
        SELECT price
        FROM tokens
        WHERE price IS NOT NULL AND trait4 = ?
        ORDER BY price DESC""",(traitId,))
        price = cur.fetchone()
        if price != None:
            price = price[0]
        cur.execute("""
        UPDATE traits SET floor = ?
        WHERE trait = ?""",(price,traitId))
conn.commit()
conn.close()
