import urllib.request, json, csv, time
APIURL ="https://api-rinkeby.etherscan.io/api?module=logs&action=getLogs&fromBlock=NEWBLOCK&toBlock=latest&address=NEWADDRESS&topic0=0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef&apikey=KRHR584Z97FWBFD923Y5XVTB4BNCNB8QAY"



mintcsv = 'Mint.csv'
purgecsv = 'Purge.csv'
savestate = "savestatePurge.csv"
gameinfo = 'gameinfo.csv'
with open(gameinfo,'r') as gameinfocsvfile:
    csvreader = csv.reader(gameinfocsvfile)
    info = next(csvreader)
    offset = int(info[1])
    address = info[2]
APIURL = APIURL.replace("NEWADDRESS", address)
with open(mintcsv,'r') as mintcsvfile:
    mintcsvreader = csv.reader(mintcsvfile)
    totalMints = len(list(mintcsvreader))


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


APIURL = APIURL.replace("NEWBLOCK", str(lastblock))

while True:
    with urllib.request.urlopen(APIURL) as url:
        data = url.read().decode()
        parser = json.loads(data)
        if parser['result'] is not None:
            number = len(parser['result'])
    c=0
    if int(parser['status']) > 0:
        while c < number:
            fromAddress = parser['result'][c]['topics'][1]
            fromAddress = fromAddress[:2]+ fromAddress[26:]
            tokenId = int(parser['result'][c]['topics'][3],16)
            toAddress =  parser['result'][c]['topics'][2]
            toAddress = toAddress[:2]+ toAddress[26:]
            purgeTime = int(parser['result'][c]['timeStamp'],16)
            tokenData = [tokenId,fromAddress,toAddress,purgeTime]
            log = parser['result'][c]['logIndex']
            log = log.zfill(10)
            Tx = parser['result'][c]['blockNumber'] + log
            Tx = int(Tx.replace("0x",""),16)
            if Tx > lastTx:
                with open(purgecsv, 'a', newline='') as csvfile: 
                    #print("writing csv", tokenData)
                    csvwriter = csv.writer(csvfile)
                    csvwriter.writerow(tokenData)
            block = int(parser['result'][c]['blockNumber'],16)
            c = c+1
        if block > lastblock:
            APIURL = APIURL.replace(str(lastblock), str(block))
        lastblock = block
        lastTx = Tx
        savestuff = [block,Tx]

        with open(savestate,'w') as savestatecsvfile:
            csvwriter = csv.writer(savestatecsvfile)
            csvwriter.writerow(savestuff)
    if Tx == endTx:
        APIURL = APIURL.replace(str(lastblock), str(block + 1))
    endTx = Tx
    time.sleep(10)
