#!/bin/bash

#use like:
#./Pub2addy.sh 02c2c5150ec7d10ebe5bbfec53d5c22cfce9fc5ba2083d6fd637cde9e999ed3b94 HUSH
#
# You CANNOT go the other way
#
# It is impossible to compute the public key of an address, as the address is computed from the hash of the public key.
# You can retrieve the public key from address with the reference client using the validateaddress RPC call (or in the debug window of Bitcoin-Qt), but that simply fetches it from the wallet, and only works if the address is your.
# Jun 13 '13 at 8:21
# Pieter Wuille

pub="$1"
addon="0"
case $2 in
KMD)
    prefix="60"
    ;;
BTC | BCH)
    prefix="00"
    addon="1"
    ;;
DGB | DOGE | PIVX)
    prefix="30"
    ;;
BTG)
    prefix="38"
    ;;
HUSH2)
    prefix="7352"
    ;;
HUSH3)
    prefix="60"
    ;;
*)
    prefix="60"
    ;;
esac

declare -a base58=(1 2 3 4 5 6 7 8 9 A B C D E F G H J K L M N P Q R S T U V W X Y Z a b c d e f g h i j k m n o p q r s t u v w x y z)
encodeBase58() {
    local n
    echo -n "$1" | sed -e's/^\(\(00\)*\).*/\1/' -e's/00/1/g' | tr -d '\n'
    dc -e "16i ${1^^} [3A ~r d0<x]dsxx +f" |
        while read -r n; do echo -n "${base58[n]}"; done
}
if [[ $addon == "1" ]]; then
    hexprefix="00"
else
    hexprefix=$(echo "obase=16;ibase=10; ${prefix}" | bc)
fi

pubsha="$(echo -n $pub |
    xxd -r -p | sha256sum | awk '{print $1}')"
echo "pubsha is: $pubsha"
ripe="$(echo -n $pubsha |
    xxd -r -p | openssl rmd160)"
ripeb=${ripe#*= }
echo "ripe is: $ripe"
plusnet="$(echo -n $ripeb |
    sed -e "s/^/$hexprefix/")"
echo "plusnet is: $plusnet"
shanet="$(echo -n $plusnet |
    xxd -r -p | sha256sum | awk '{print $1}')"
reshanet="$(echo -n $shanet |
    xxd -r -p | sha256sum | awk '{print $1}')"
leadbits="$(echo -n $reshanet | sed 's/^\(.\{8\}\).*/\1/')"
mash="$plusnet$leadbits"
echo "mash is: $mash"
address="$(encodeBase58 "$mash")"
echo "Address is: $address"
exit 1
