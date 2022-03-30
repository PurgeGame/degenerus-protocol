import sqlite3,csv

address = '0x7C94325Ad8dc46067F15918883933596aC31801F'
purge = 'purge.csv'

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId
    FROM tokens
    WHERE holderaddress =? and trait4 = ?""",(address,246))
tokens = cur.fetchall()
savestuff = []
for row in tokens:
    savestuff.append(row[0])

with open(purge,'w') as savestatecsvfile:
    csvwriter = csv.writer(savestatecsvfile)
    csvwriter.writerow(savestuff)
