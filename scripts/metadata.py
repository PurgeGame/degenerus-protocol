import urllib.request, time
import os
from dotenv import load_dotenv
load_dotenv()
address = os.environ.get("ADDRESS")

for c in range(1,2886):
    print(c)
    url ='https://rinkeby-api.opensea.io/api/v1/asset/' + address + '/' + str(c) + '/?force_update=true'
    page=urllib.request.Request(url,headers={'User-Agent': 'Mozilla/5.0'})
    urllib.request.urlopen(page)
    time.sleep(1)