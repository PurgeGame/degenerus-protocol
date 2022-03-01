import urllib.request, json, csv, time
APIURL ="https://api-rinkeby.etherscan.io/api?module=logs&action=getLogs&fromBlock=NEWBLOCK&toBlock=latest&address=NEWADDRESS&topic0=0xab34f200d3aaf6dad5697c4463419f77d03f915e1eae32ff192c72701eae5c4a&apikey=KRHR584Z97FWBFD923Y5XVTB4BNCNB8QAY"

address = "0x13a6CB88A0d6D2Af1aEf78Dd4F0f9C2E9d4f1B97"
APIURL = APIURL.replace("NEWADDRESS", address)

mintcsv = 'Purge.csv'
savestate = "savestatePurge.csv"
offset = 420

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
            purgeAddress = parser['result'][c]['topics'][1]
            purgeAddress = purgeAddress[:2]+ purgeAddress[26:]
            tokenId = int(parser['result'][c]['data'],16)
            if tokenId-offset < 1 :
                tokenId = totalMints - (offset - tokenId)
            else:
                tokenId -= offset
            tokenData = [tokenId,purgeAddress]

            with open(mintcsv, 'a', newline='') as csvfile: 
                print("writing csv", tokenData)
                csvwriter = csv.writer(csvfile)
                csvwriter.writerow(tokenData)
            block = int(parser['result'][c]['blockNumber'],16) + 1
            c = c+1

        APIURL = APIURL.replace(str(lastblock), str(block))
        lastblock = [block,0] 

        with open(savestate,'w') as savestatecsvfile:
            csvwriter = csv.writer(savestatecsvfile)
            csvwriter.writerow(lastblock)
    time.sleep(60)
