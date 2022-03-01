import json, csv


mintcsv = 'Mint.csv'
traitmap = 'Traitmap.csv'
counter = 0
traitCount = [0] * 256
with open(mintcsv,'r') as mintcsvfile:
    mintcsvreader = csv.reader(mintcsvfile)
    for row in mintcsvreader:  
        tokenTraits = row
 
        for c in range(1,5):
            
            traitCount[int(tokenTraits[c])] += 1
        countertwo = 0
        for c in range(0,255):

            if traitCount[c] < 3:
                countertwo += 1
        if countertwo <10 and countertwo < oldcountertwo:
            print(str(counter) + "  " + str(countertwo) )
        counter +=1
        oldcountertwo = countertwo



