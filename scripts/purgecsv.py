import sqlite3,csv

address = '0x8C6dE94FfEc33EE24097632b033698cBB8b7F741'
purge = 'purge.csv'

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId
    FROM tokens
    WHERE holderaddress =? and trait2 = ?""",(address,124))
tokens = cur.fetchall()
savestuff = []
for row in tokens:
    savestuff.append(row[0])

with open(purge,'w') as savestatecsvfile:
    csvwriter = csv.writer(savestatecsvfile)
    csvwriter.writerow(savestuff)
