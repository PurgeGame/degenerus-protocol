import urllib.request, json, csv, time
APIURL ="https://api-rinkeby.etherscan.io/api?module=logs&action=getLogs&fromBlock=NEWBLOCK&toBlock=latest&address=NEWADDRESS&topic0=0x7f8762ce295712e6d6106b57b29d7ba732a525b207b361f1400e562ae7928e61&apikey=85ZYSGI6DCYIAAWPZ38XTM6CSM5XZBHW9P"




mintcsv = 'MintandPurge.csv'
savestate = "savestateMAP.csv"
gameinfo = 'gameinfo.csv'
with open(gameinfo,'r') as gameinfocsvfile:
    csvreader = csv.reader(gameinfocsvfile)
    info = next(csvreader)
    address = info[2]
APIURL = APIURL.replace("NEWADDRESS", address)

with open(savestate,'r') as savestatecsvfile:
    csvreader = csv.reader(savestatecsvfile)
    save = next(csvreader)
if int(save[0]) !=0:
    lastblock = int(save[0])
else:
    lastblock = 379224
lasttokenId = int(save[1])

APIURL = APIURL.replace("NEWBLOCK", str(lastblock))
done = 0
while done == 0:
    with urllib.request.urlopen(APIURL) as url:
        data = url.read().decode()
        parser = json.loads(data)
        if parser['result'] is not None:
            number = len(parser['result'])
    c=0 
    if int(parser['status']) > 0:
        while c < number:
            tokenTraits = parser['result'][c]['topics'][1]
            tokenTraits = int(tokenTraits, 16)
            tokenTraitOne = tokenTraits & 0x3f
            tokenTraitTwo = ((tokenTraits & 0xfc0) >> 6) + 64
            tokenTraitThree = ((tokenTraits & 0x3f000) >> 12) + 128
            tokenTraitFour = ((tokenTraits & 0xfc0000) >> 18) + 192
            tokenId = parser['result'][c]['data']
            tokenId = int(tokenId,16)
            purgeAddress = parser['result'][c]['topics'][2]
            purgeAddress = purgeAddress[:2]+ purgeAddress[26:]
            purgeTime = int(parser['result'][c]['timeStamp'],16)
            tokenData = [tokenId,tokenTraitOne,tokenTraitTwo,tokenTraitThree,tokenTraitFour,purgeAddress,purgeTime]
            if tokenId > lasttokenId:
                with open(mintcsv, 'a', newline='') as csvfile: 
                    print("writing csv", tokenData)
                    csvwriter = csv.writer(csvfile)
                    csvwriter.writerow(tokenData)
                    lasttokenId = tokenId
            block = int(parser['result'][c]['blockNumber'],16)+1
            c = c+1

        APIURL = APIURL.replace(str(lastblock), str(block))
        lastblock = block 
        savestuff = [lastblock,tokenId]
        with open(savestate,'w') as savestatecsvfile:
            csvwriter = csv.writer(savestatecsvfile)
            csvwriter.writerow(savestuff)
        time.sleep(10)
    else:
        done =1
