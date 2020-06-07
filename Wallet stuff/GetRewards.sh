#!/bin/bash
SHELL=/bin/sh PATH=/bin:/sbin:/usr/bin:/usr/sbin
#
# You MUST have jq installed for this to work https://stedolan.github.io/jq/download/
#
# use like: ./GetRewards.sh RJ8q5vbzEiSRNeAu39xYfawuTa9djYEsQK
# or        ./GetRewards.sh
#
# using no address will scan the whole wallet

cd $HOME/komodo/src # komodo-cli location

txfee="0.00000035" # because I'm a cheap bastid
maxconf=$(./komodo-cli getblockcount) maxconf=$((maxconf + 1))
echo "Finding UTXOS in $maxconf blocks to claim ..."

Addy=""
if [ "${1}" = "" ]; then
    unspents=$(./komodo-cli listunspent 1 $maxconf)
else
    Addy=${1}
    unspents=$(./komodo-cli listunspent 1 $maxconf [\"$Addy\"])
fi
enabled="y"

inputUTXOs=$(jq -r '[map(select(( .spendable | contains(true)) and (.interest > 0.00000000))) | .[] | {address, txid, vout, amount, interest}]' <<<"${unspents}")
UTXOcount=$(jq -r '.|length' <<<"${inputUTXOs}")
echo "Found $UTXOcount UTXOs bearing rewards...."
function addnlocktime() {
    #nlocktime=$(printf "%08x" $(date +%s) | dd conv=swab 2>/dev/null | rev)
	nlocktime="00000000"
    chophex=$(echo $createhex | sed 's/.\{38\}$//')
    nExpiryHeight=$(echo $createhex | grep -o '.\{30\}$')
    newhex=$chophex$nlocktime$nExpiryHeight
}

if [[ $enabled == "y" ]]; then
    for txid in $(jq -r '.[].txid' <<<"${inputUTXOs}"); do txids+=("$txid"); done
    for address in $(jq -r '.[].address' <<<"${inputUTXOs}"); do addresses+=("$address"); done
    for vout in $(jq -r '.[].vout' <<<"${inputUTXOs}"); do vouts+=("$vout"); done
    for amount in $(jq -r '.[].amount' <<<"${inputUTXOs}"); do
        if [[ "$amount" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            amounts+=("$amount")
        else
            amounts+=("$(printf "%.8f" $amount)")
        fi
    done
    for reward in $(jq -r '.[].interest' <<<"${inputUTXOs}"); do
        if [[ "$reward" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            rewards+=("$reward")
        else
            rewards+=("$(printf "%.8f" $reward)")
        fi
    done
    for ((tc = 0; tc <= ${#vouts[@]} - 1; tc++)); do
        OutAmount=$(echo "scale=8; ((${amounts[tc]} + ${rewards[tc]}) - $txfee)" | bc)
        RawOut="[{\"txid\":\"${txids[tc]}\",\"vout\":${vouts[tc]}}] {\"${addresses[tc]}\":$OutAmount}"
        createhex=$(./komodo-cli createrawtransaction $RawOut)
        addnlocktime
        Signed=$(./komodo-cli signrawtransaction $newhex | jq -r '.hex')
        sendit=$(echo -e "$Signed" | ./komodo-cli $AssetChain -stdin sendrawtransaction)
        echo "${addresses[tc]} got ${rewards[tc]} rewards on ${amounts[tc]} through txid:$sendit"
    done

else
    echo "${inputUTXOs[0]}"
fi
exit 1
