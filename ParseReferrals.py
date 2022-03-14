import urllib.request, json, csv, time
from web3 import Web3
APIURL ="https://api-rinkeby.etherscan.io/api?module=logs&action=getLogs&fromBlock=NEWBLOCK&toBlock=latest&address=NEWADDRESS&topic0=0xd2ca91448cfa55c5df70273934d20f101c11eb4a3e4ac1a28550bbf792b1377d&apikey=KRHR584Z97FWBFD923Y5XVTB4BNCNB8QAY"





refercsv = 'Referrals.csv'
savestate = "savestateReferrals.csv"
gameinfo = 'gameinfo.csv'
with open(gameinfo,'r') as gameinfocsvfile:
    csvreader = csv.reader(gameinfocsvfile)
    info = next(csvreader)
    address = info[2]

with open(savestate,'r') as savestatecsvfile:
    csvreader = csv.reader(savestatecsvfile)
    save = next(csvreader)
if int(save[0]) !=0:
    lastblock = int(save[0])
else:
    lastblock = 379224
if int(save[1]) !=0:
    lastTx = int(save[1])
else:
    lastTx = 0
endTx = lastTx

APIURL = APIURL.replace("NEWADDRESS", address)
APIURL = APIURL.replace("NEWBLOCK", str(lastblock))
endTx = lastTx
while True:
    with urllib.request.urlopen(APIURL) as url:
        data = url.read().decode()
        parser = json.loads(data)
        if parser['result'] is not None:
            number = len(parser['result'])
    c=0
    if int(parser['status']) > 0:
        while c < number:
            referAddress = parser['result'][c]['topics'][1]
            print(referAddress)
            referAddress = referAddress[:2]+ referAddress[26:]
            quantity = parser['result'][c]['topics'][2]
            quantity = int(quantity[26:], 16)
            data = [referAddress, quantity]
            log = parser['result'][c]['logIndex']
            log = log.zfill(10)
            Tx = parser['result'][c]['blockNumber'] + log
            Tx = int(Tx.replace("0x",""),16)
            if Tx > lastTx:
                with open(refercsv, 'a', newline='') as csvfile: 
                    print("writing csv", data)
                    csvwriter = csv.writer(csvfile)
                    csvwriter.writerow(data)
            block = int(parser['result'][c]['blockNumber'],16) + 1
            c = c+1

        APIURL = APIURL.replace(str(lastblock), str(block))
        lastblock = block
        savestuff = [block,Tx]
        with open(savestate,'w') as savestatecsvfile:
            csvwriter = csv.writer(savestatecsvfile)
            csvwriter.writerow(savestuff)
    if Tx == endTx:
        APIURL = APIURL.replace(str(lastblock), str(block + 1))
    endTx = Tx
    time.sleep(60)
