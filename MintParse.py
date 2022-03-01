import urllib.request, json, csv, time
APIURL ="https://api-rinkeby.etherscan.io/api?module=logs&action=getLogs&fromBlock=NEWBLOCK&toBlock=latest&address=NEWADDRESS&topic0=0x15b2b173cc0f2d399a1c7463d3ed2745e1b42c8b8d5bc6c17b905336076c0486&apikey=KRHR584Z97FWBFD923Y5XVTB4BNCNB8QAY"

address = "0x988661BAE9C0BBd7611785a414Df5fffaD5A2fA6"
APIURL = APIURL.replace("NEWADDRESS", address)

mintcsv = 'Mint.csv'
savestate = "savestate.csv"
with open(savestate,'r') as savestatecsvfile:
    csvreader = csv.reader(savestatecsvfile)
    save = next(csvreader)
if int(save[0]) !=0:
    lastblock = int(save[0])
else:
    lastblock = 379224
lasttokenId = int(save[1])

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
            tokenTraits = parser['result'][c]['topics'][1]
            tokenTraits = int(tokenTraits, 16)
            tokenTraitOne = tokenTraits & 0x3f
            tokenTraitTwo = ((tokenTraits & 0xfc0) >> 6) + 64
            tokenTraitThree = ((tokenTraits & 0x3f000) >> 12) + 128
            tokenTraitFour = ((tokenTraits & 0xfc0000) >> 18) + 192
            tokenId = parser['result'][c]['data']
            tokenId = int(tokenId,16)
            tokenData = [tokenId,tokenTraitOne,tokenTraitTwo,tokenTraitThree,tokenTraitFour]

            if tokenId > lasttokenId:
                with open(mintcsv, 'a', newline='') as csvfile: 
                    print("writing csv", tokenData)
                    csvwriter = csv.writer(csvfile)
                    csvwriter.writerow(tokenData)
                    lasttokenId = tokenId
            block = int(parser['result'][c]['blockNumber'],16)
            c = c+1

        APIURL = APIURL.replace(str(lastblock), str(block))

        lastblock = block 
        savestuff = [lastblock,tokenId]
        with open(savestate,'w') as savestatecsvfile:
            csvwriter = csv.writer(savestatecsvfile)
            csvwriter.writerow(savestuff)
    time.sleep(60)
