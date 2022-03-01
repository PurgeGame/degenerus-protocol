import json, csv
from lib2to3.pgen2 import token


mintcsv = 'Mint.csv'
traitmap = 'Traitmap.csv'
ifps = 'ipfs://QmdvkbjDQr9bqzCMJFinKvxuPX57owMkZuoAhSf71uDoeK/'
offset = 420


with open(mintcsv,'r') as mintcsvfile:
    
    mintcsvreader = csv.reader(mintcsvfile)
    totalMints = len(list(mintcsvreader))
    mintcsvfile.seek(0)
    for row in mintcsvreader:
        tokenTraits = row
        tokenTraitsString = []
        for c in range(1,5):

            with open(traitmap,'r') as traitmapcsvfile:
                traitmapcsvreader = csv.reader(traitmapcsvfile)
                traitStrings = next(traitmapcsvreader)

                traitColor = traitStrings[int((int(tokenTraits[c]) - (c-1) * 64) / 8)]
                for count in range(1,c+1):
                    traitStrings = next(traitmapcsvreader)
                traitAttribute = traitStrings[(int(tokenTraits[c]) - (c-1) * 64) % 8]
                tokenTraitsString.append(traitColor +" " + traitAttribute)

        #tokenName = 'Purge Game Season One # ' + tokenTraits[0]
        tokenId = int(tokenTraits[0])
        if tokenId-offset < 1 :
            tokenId = totalMints - (offset - tokenId)
        else:
            tokenId -= offset
        tokenName = 'Purge Game Season One # ' + str(tokenId)
        image = ifps + str(tokenId) + '.png'
        data = {
            'name': tokenName,
            'description': 'Purge Game token',
            'image' : image,
            'attributes': [
            {
                'trait_type': 'Crypto', 'value' : tokenTraitsString[0]
            },
            {
                'trait_type': 'Letter', 'value': tokenTraitsString[1]
            },
            {
                'trait_type': 'Symbol', 'value': tokenTraitsString[2]
            },
            {
                'trait_type': 'Number', 'value': tokenTraitsString[3]
            }
            ]
         }
        json_string = json.dumps(data)
        


        outputfile = "json\\"+str(tokenId)
        print (outputfile)
        with open(outputfile, "w") as outfile:
            outfile.write(json_string)
            #print(data)