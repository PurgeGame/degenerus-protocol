import random,sqlite3
from email.mime import image
from PIL import Image

conn = sqlite3.connect('PurgeGame.db')
cur = conn.cursor()
cur.execute("""
    SELECT tokenId,trait1,trait2,trait3,trait4
    FROM tokens""")
tokens = cur.fetchall()
for row in tokens:
    tokenId = row[0]
    traitimagefile = []
    color = []
    if tokenId >30000:
        tokenIdfilename="MAPImages\\" + str(tokenId) + '.png'
    else:
        tokenIdfilename = "finished\\" +str(tokenId) + '.png'
    for c in range(1,5):
        cur.execute("""
        SELECT color,shape
        FROM traits
        WHERE trait =?""",(row[c],))
        trait = cur.fetchone()
        color.append(trait[0])
        trait = trait[0] + " " + trait[1]
        trait = trait.lower()
        trait = trait.replace(" ", "_")
        traitimagefile.append("baseimages\\" + trait + ".png")

    colors = ['Brown','Orange','Pink','Red','Green','Purple','Blue']
    colors = list(set(colors)-set(color))
    colorfound = random.choice(colors).lower()

    background = Image.open("baseimages\\background" + colorfound + ".png")
    background = background.convert("RGBA")
    traitimageone = Image.open(traitimagefile[0])
    traitimageone = traitimageone.resize((250,250))
    traitimageone = traitimageone.convert("RGBA")
    Image.Image.paste(background,traitimageone,(42,42), traitimageone)
    traitimagetwo = Image.open(traitimagefile[1])
    traitimagetwo = traitimagetwo.resize((250,250))
    traitimageone = traitimagetwo.convert("RGBA")
    Image.Image.paste(background,traitimagetwo, (348,42),traitimagetwo)
    traitimagethree = Image.open(traitimagefile[2])
    traitimagethree = traitimagethree.resize((250,250))
    traitimageone = traitimagethree.convert("RGBA")
    Image.Image.paste(background,traitimagethree, (42,348),traitimagethree)
    traitimagefour = Image.open(traitimagefile[3])
    traitimagefour = traitimagefour.resize((250,250))
    traitimageone = traitimagefour.convert("RGBA")
    Image.Image.paste(background,traitimagefour, (348,348),traitimagefour)
    background.save(tokenIdfilename)
    smaller = background.resize((320,320))
    smaller.save("smalltokens\\" +str(tokenId) + '.png')

bomb = Image.open('baseimages\\bomb.png')
bomb = bomb.convert("RGBA")
background = Image.open("baseimages\\background" + colorfound + ".png")
Image.Image.paste(background,bomb, (0,0),bomb)
background.save('finished\\bomb.png')
background.save('smalltokens\\bomb.png')
print('done')