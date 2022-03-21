import sqlite3,csv

address = '0x89a86be0EfFe52682222212d74913b497eecd506'
purge = 'purge.csv'

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId
    FROM tokens
    WHERE holderaddress =? and trait1 = ?""",(address,63))
tokens = cur.fetchall()
savestuff = []
for row in tokens:
    savestuff.append(row[0])

with open(purge,'w') as savestatecsvfile:
    csvwriter = csv.writer(savestatecsvfile)
    csvwriter.writerow(savestuff)
