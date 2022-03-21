import sqlite3,csv

address = '0x0FEf8389161b0f7C43866D03d934B40Cf6B745eB'
purge = 'purge.csv'

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId
    FROM tokens
    WHERE holderaddress =? and trait2 = ?""",(address,71))
tokens = cur.fetchall()
savestuff = []
for row in tokens:
    savestuff.append(row[0])

with open(purge,'w') as savestatecsvfile:
    csvwriter = csv.writer(savestatecsvfile)
    csvwriter.writerow(savestuff)
