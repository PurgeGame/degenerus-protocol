import csv
from email.mime import image
from PIL import Image


mintcsv = 'Mint.csv'
traitmap = 'Traitmap.csv'
offset = 0


with open(mintcsv,'r') as mintcsvfile:
    mintcsvreader = csv.reader(mintcsvfile)
    totalMints = len(list(mintcsvreader))
    mintcsvfile.seek(0)
    for row in mintcsvreader:  
        tokenTraits = row
        tokenId = int(tokenTraits[0])
        if tokenId < 40000:
            if tokenId-offset < 1 :
                tokenId = totalMints - (offset - tokenId)
            else:
                tokenId -= offset
        tokenIdfilename = "finished\\" +str(tokenId) + '.png'
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
                traitimagefile = tokenTraitsString
        for x in range(0,4):
            traitimagefile[x] = traitimagefile[x].lower()
            traitimagefile[x] = traitimagefile[x].replace(" ", "_")
            traitimagefile[x] = "baseimages\\" + traitimagefile[x] + ".png"

        background = Image.open("baseimages\\background.png")
        background = background.convert("RGBA")
        traitimageone = Image.open(traitimagefile[0])
        traitimageone = traitimageone.resize((250,250))
        traitimageone = traitimageone.convert("RGBA")
        Image.Image.paste(background,traitimageone,(35,35), traitimageone)
        traitimagetwo = Image.open(traitimagefile[1])
        traitimagetwo = traitimagetwo.resize((250,250))
        traitimageone = traitimagetwo.convert("RGBA")
        Image.Image.paste(background,traitimagetwo, (355,35),traitimagetwo)
        traitimagethree = Image.open(traitimagefile[2])
        traitimagethree = traitimagethree.resize((250,250))
        traitimageone = traitimagethree.convert("RGBA")
        Image.Image.paste(background,traitimagethree, (35,355),traitimagethree)
        traitimagefour = Image.open(traitimagefile[3])
        traitimagefour = traitimagefour.resize((250,250))
        traitimageone = traitimagefour.convert("RGBA")
        Image.Image.paste(background,traitimagefour, (355,355),traitimagefour)
        background.save(tokenIdfilename)
            

           