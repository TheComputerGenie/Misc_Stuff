#!/usr/bin/env python3
import hashlib
import base58
import binascii


#BC = KMD
#80 = BTC
#A6 = GAME
#B0 = EMC2
#C6 = GIN
#BF = SUQA
#B0 = AYA
prefixList = ['KMD', 'BC', 'BTC', '80', 'GAME', 'A6', 'EMC2', 'B0', 'GIN', 'C6', 'SUQA', 'BF', 'AYA', 'B0']
private_key_WIF = input('Enter WIF: ')

first_encode = base58.b58decode(private_key_WIF)

private_key_full = binascii.hexlify(first_encode)
private_key = private_key_full[2:-8]
private_key_static = private_key.decode("utf-8")

print('privkey:',private_key_static)

for iprefix in range(len(prefixList)) :
    spot = iprefix%2
    if spot != 0:
        extended_key = prefixList[iprefix]+private_key_static
        first_sha256 = hashlib.sha256(binascii.unhexlify(extended_key)).hexdigest()
        second_sha256 = hashlib.sha256(binascii.unhexlify(first_sha256)).hexdigest()
        final_key = extended_key+second_sha256[:8]
        WIF = base58.b58encode(binascii.unhexlify(final_key))

        print ('WIF:', WIF.decode("utf-8"))
    else:
        print(prefixList[iprefix])