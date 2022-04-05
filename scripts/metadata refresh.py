import urllib.request, time

for c in range(1,2000):
    print(c)
    url ='https://rinkeby-api.opensea.io/api/v1/asset/0x3973A924Fdc47f7FA11565399A7d65Bb76d3D89a/' + str(c) + '/?force_update=true'
    page=urllib.request.Request(url,headers={'User-Agent': 'Mozilla/5.0'})
    urllib.request.urlopen(page)
    time.sleep(1)