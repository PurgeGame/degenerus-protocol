#!/bin/bash
rm /var/scripts/finished/*.png
rm /var/scripts/MAPImages/*.png
rm /var/scripts/smallimages/*.png
rm /var/www/purge.game/public_html/tokens/*.png
rm /var/www/purge.game/public_html/lgtokens/*.png
python3 /var/scripts/imagecreator.py
cp /var/scripts/smallimages/*.png /var/www/purge.game/public_html/tokens/
cp /var/scripts/finished/*.png /var/www/purge.game/public_html/lgtokens/
cp /var/scripts/MAPImages/*.png /var/www/purge.game/public_html/lgtokens/

