#!/bin/bash
SHELL=/bin/sh PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
#
#
#This will consolidate all mining rewards, change, and "stale" UTXOs  (but not the needed splits)
#
#
Addy=RCGxNA1xHinKkcC6gf7BpxAt3wLeqcpch4

cd $HOME/komodo/src #komodo-cli location
komodo-cli lockunspent true $(komodo-cli listlockunspent | jq -c .)
maxInc="1200"
MinCheck="1" RawOut="[" OutAmount="0"
maxconf=$(./komodo-cli getblockcount) maxconf=$((maxconf + 1))
txids=() vouts=() amounts=()
SECONDS=0
echo "Finding UTXOS in $maxconf blocks to consolidate ..."
unspents=$(./komodo-cli listunspent $MinCheck $maxconf)
inputUTXOs=$(jq -cr '[map(select(((.spendable == true and .confirmations > 2880) or (.spendable == true and (.amount|tonumber) > 0.0001)))) | .[] | {txid, vout, amount}]' <<<"${unspents}")
UTXOcount=$(jq -r '.|length' <<<"${inputUTXOs}")
duration=$SECONDS
echo "Found $UTXOcount UTXOs.... $(($duration % 60)) seconds"
function makeRaw() {
    for ((tc = 0; tc <= $1 - 1; tc++)); do
        RawOut2="{\"txid\":\"${txids[tc]}\",\"vout\":${vouts[tc]}},"
        RawOut="$RawOut$RawOut2"
        OutAmount=$(echo "scale=8; ($OutAmount + ${amounts[tc]})" | bc)
    done
    OutAmount=$(echo "scale=8; $OutAmount - 0.00001" | bc) OutAmount=${OutAmount/#./0.}
    RawOut="${RawOut::-1}" RawOut=$RawOut"] {\"$Addy\":$OutAmount}"
}
function addnlocktime() {
    #nlocktime=$(printf "%08x" $(date +%s) | dd conv=swab 2>/dev/null | rev)
	nlocktime="00000000"
    chophex=$(echo $toSign | sed 's/.\{38\}$//')
    nExpiryHeight=$(echo $toSign | grep -o '.\{30\}$')
    newhex=$chophex$nlocktime$nExpiryHeight
}
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
    toSign=$(./komodo-cli createrawtransaction $RawOut)
    addnlocktime
    Signed=$(./komodo-cli signrawtransaction $newhex | jq -r '.hex')
    lasttx=$(echo -e "$Signed" | ./komodo-cli -stdin sendrawtransaction)
    echo "Consolidated $(jq '. | length' <<<"${RawOut}") UTXOs:"
    duration=$SECONDS
    echo "Sent signed raw consolidated tx: $lasttx for $OutAmount $ac_name $(($duration % 60)) seconds"

    txids=("${txids[@]:$maxInc}")
    vouts=("${vouts[@]:$maxInc}")
    amounts=("${amounts[@]:$maxInc}")
    RawOut="[" OutAmount="0"
    sleep 10
done
exit 1
