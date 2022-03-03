import csv
traitmap = 'Traitmap.csv'
categories = ["crypto", "letters", "symbols","numbers"]
rarity = ["common","common","common","rare","rare","rare","uncommon","uncommon","uncommon"]

with open(traitmap,'r') as traitmapcsvfile:
    traitmapcsvreader = csv.reader(traitmapcsvfile)
    colors = next(traitmapcsvreader)
    scriptfile = open("script.ds","a")
    for y in range(0,4):
        symbols = next(traitmapcsvreader)
        for c in range(0,8):
            category = categories[y] + " " + rarity[c]
            if c == 0 or c == 3 or c == 6:
                scriptfile.write("create category " + '"' + category + '"' + "\n")
            traitColor = colors[c]
            for x in range(0,8):
                traitSymbol = symbols[x]
                print(traitSymbol)
                trait = traitColor + " " + traitSymbol
                channel = trait.replace(" ", "-")
                scriptfile.write("create text channel " + '"' + trait + '" ' + "category " + '"' + category + '"' + "\n")
                if y == 3 and (c == 0 or c == 1 or c == 2):
                    scriptfile.write("configure permissions for " + '"common ' + traitSymbol + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
                else:
                    scriptfile.write("configure permissions for " + '"' + trait + '" ' + "on " + channel + " allow view_channel send_messages default"+ "\n")
                



