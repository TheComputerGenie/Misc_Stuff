#!/bin/bash
SHELL=/bin/sh PATH=/bin:/sbin:/usr/bin:/usr/sbin
#
# You MUST have jq installed for this to work https://stedolan.github.io/jq/download/
#
# use like: ./Consolidate.sh SUPERNET RJ8q5vbzEiSRNeAu39xYfawuTa9djYEsQK
#

cd $HOME/komodo_beta/src #komodo-cli location

AssetChain=""
if [ "${1}" = "" ]; then
    echo "Need a chain to consolidate"
    exit 1
elif [ "${1}" != "KMD" ]; then
    AssetChain=" -ac_name="${1}
fi
ac_name=${1}

Addy=""
if [ "${2}" = "" ]; then
    echo "Need an address to send to"
    exit 1
fi
Addy=${2}

enabled="y"

maxInc="800" MinCheck="1" RawOut="[" OutAmount="0"
maxconf=$(./komodo-cli$AssetChain getblockcount) maxconf=$((maxconf + 1))
txids=() vouts=() amounts=()
SECONDS=0
echo "Finding UTXOS in $maxconf blocks to consolidate ..."
unspents=$(./komodo-cli$AssetChain listunspent $MinCheck $maxconf)
inputUTXOs=$(jq -cr '[map(select(.spendable == true and .confirmations > 1)) | .[] | {txid, vout, amount}]' <<<"${unspents}")
UTXOcount=$(jq -r '.|length' <<<"${inputUTXOs}")
duration=$SECONDS
echo "Found $UTXOcount UTXOs.... $(($duration % 60)) seconds"

function makeRaw() {
    for ((tc = 0; tc <= $1 - 1; tc++)); do
        RawOut2="{\"txid\":\"${txids[tc]}\",\"vout\":${vouts[tc]}},"
        RawOut="$RawOut$RawOut2"
        OutAmount=$(echo "scale=8; ($OutAmount + ${amounts[tc]})" | bc)
    done
    OutAmount=$(echo "scale=8; $OutAmount - 0.0001" | bc) OutAmount=${OutAmount/#./0.}
    RawOut="${RawOut::-1}" RawOut=$RawOut"] {\"$Addy\":$OutAmount}"
}
function addnlocktime() {
    #nlocktime=$(printf "%08x" $(date +%s) | dd conv=swab 2>/dev/null | rev)
	nlocktime="00000000"
    chophex=$(echo $toSign | sed 's/.\{38\}$//')
    nExpiryHeight=$(echo $toSign | grep -o '.\{30\}$')
    newhex=$chophex$nlocktime$nExpiryHeight
}

if [[ $enabled == "y" ]]; then
    LoopsCount=$(echo "scale=0; ($UTXOcount / $maxInc)" | bc)
    echo "This will take $LoopsCount transaction(s) to complete...."
    SECONDS=0
    for txid in $(jq -r '.[].txid' <<<"${inputUTXOs}"); do txids+=("$txid"); done
    duration=$SECONDS
    echo "Captured txids... $(($duration % 60)) seconds"
    SECONDS=0
    for vout in $(jq -r '.[].vout' <<<"${inputUTXOs}"); do vouts+=("$vout"); done
    duration=$SECONDS
    echo "Captured vouts... $(($duration % 60)) seconds"
    SECONDS=0
    for amount in $(jq -r '.[].amount' <<<"${inputUTXOs}"); do
        if [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            amounts+=("$amount")
        else
            amounts+=("$(printf "%.8f" $amount)")
        fi
    done
    duration=$SECONDS
    echo "Captured amounts... $(($duration % 60)) seconds"
    echo "Packed and ready to begin...."
    for ((tlc = 0; tlc <= $LoopsCount; tlc++)); do
        echo "${#vouts[@]} UTXOs left to consolitate..."
        SECONDS=0
        if [[ ${#vouts[@]} -ge $maxInc ]]; then
            makeRaw $maxInc
        else
            makeRaw ${#vouts[@]}
        fi
        duration=$SECONDS
        echo "Created raw consolidated tx $(($duration % 60)) seconds"
        #echo $RawOut
        SECONDS=0
        toSign=$(./komodo-cli$AssetChain createrawtransaction $RawOut)
        addnlocktime
        Signed=$(./komodo-cli$AssetChain signrawtransaction $newhex | jq -r '.hex')
        lasttx=$(echo -e "$Signed" | ./komodo-cli $AssetChain -stdin sendrawtransaction)
        echo "Consolidated $(jq '. | length' <<<"${RawOut}") UTXOs:"
        duration=$SECONDS
        echo "Sent signed raw consolidated tx: $lasttx for $OutAmount $ac_name  $(($duration % 60)) seconds"

        txids=("${txids[@]:$maxInc}")
        vouts=("${vouts[@]:$maxInc}")
        amounts=("${amounts[@]:$maxInc}")
        RawOut="[" OutAmount="0"
        sleep 30
    done

else
    echo "${unspents}"
fi
exit 1
