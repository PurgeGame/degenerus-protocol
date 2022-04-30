import json


ifps = 'ipfs://QmPeRLtfzAv9srKUyARApmQj8fwUuozBGZ3pyzmtsiNmou'

for c in range(1,39421):
    data = {
        'name': 'Unrevealed #' + str(c),
        'description': 'Unrevealed Purge Game token',
        'image' : ifps,
        'attributes': []
        }
    json_string = json.dumps(data)
    outputfile = "json\\"+str(c)
    with open(outputfile, "w") as outfile:
        outfile.write(json_string)