import sqlite3,urllib.request
import json, time
from web3 import Web3
import os


address = os.environ.get("ADDRESS")
ALCHEMY_API = os.environ.get("ALCHEMY_API")
ETHERSCAN_API_ONE = os.environ.get("ETHERSCAN_API_ONE")

alchemy_url = 'https://eth-rinkeby.alchemyapi.io/v2/'+ALCHEMY_API
web3 = Web3(Web3.HTTPProvider(alchemy_url))


ESAPI = 'https://api-rinkeby.etherscan.io/api?module=contract&action=getabi&address=' + address + '&apikey=' + ETHERSCAN_API_ONE
with urllib.request.urlopen(ESAPI) as url:
    data = url.read().decode()
    contractabi = json.loads(data)['result']
address = Web3.toChecksumAddress(address)
contract = web3.eth.contract(address= address, abi=contractabi)

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT remaining
    FROM traits""")
db = cur.fetchall()

for c in range(0,256):
    con = contract.caller.traitRemaining(c)
    if db[c][0] != con:
        print(c,db[c][0],con)
print('done')