#!/bin/bash
SHELL=/bin/sh PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
#
# You MUST have bc and jq installed for this to work (jq: https://stedolan.github.io/jq/download/)
# Assumes used `sudo make install` inside komodo dir
#
# use like: ./Consolidate.sh KMD RCGxKMDxZcBGRZkxvgCRAXGpiQFt8wU7Wq
#       or: ./Consolidate.sh TOKEL RCGxKMDxZcBGRZkxvgCRAXGpiQFt8wU7Wq
#
# ***CONSOLIDATES ALL SPENDABLE UTXOS***
# DO NOT use if wallet contains addresses you don't want associated with each other
#
AssetChain=""
if [ "${1}" = "" ]; then
    echo "Need a chain to consolidate"
    exit 1
elif [ "${1}" != "KMD" ]; then
    AssetChain=" -ac_name="${1}
fi

Addy=""
if [ "${2}" = "" ]; then
    echo "Need an address to send to"
    exit 1
fi
Addy=${2}
enabled="y"

maxInc="800" MinCheck="1" OutAmount="0" RawInputs="["
maxconf=$(komodo-cli${AssetChain} getblockcount) maxconf=$((maxconf + 1))
txids=() vouts=() amounts=()
SECONDS=0
echo "Finding UTXOs in ${maxconf} blocks to consolidate ..."
unspents=$(komodo-cli${AssetChain} listunspent ${MinCheck} ${maxconf})
inputUTXOs=$(jq -cr '[map(select(.spendable == true and .confirmations > 1))|.[]|{txid, vout, amount, confirmations}]|sort_by(.confirmations)' <<<"${unspents}")
UTXOcount=$(jq -r '.|length' <<<"${inputUTXOs}")
duration=$SECONDS
echo "Found ${UTXOcount} UTXOs.... $(($duration % 60)) seconds"

waitforconfirm() {
    confirmations=0
    while [[ ${confirmations} -lt 1 ]]; do
        sleep 1
        confirmations=$(jq -r .confirmations <<<"$(komodo-cli${AssetChain} gettransaction ${1} 2>/dev/null)") >/dev/null 2>&1
        komodo-cli${AssetChain} sendrawtransaction $(komodo-cli${AssetChain} getrawtransaction ${1} 2>/dev/null) >/dev/null 2>&1
    done
}
function makeRaw() {
    for ((tc = 0; tc <= $1 - 1; tc++)); do
        RawInputs2="{\"txid\":\"${txids[tc]}\",\"vout\":${vouts[tc]}},"
        RawInputs="${RawInputs}${RawInputs2}"
        OutAmount=$(bc <<<"scale=8; (${OutAmount} + ${amounts[tc]})")
    done
    OutAmount=$(bc <<<"scale=8; ${OutAmount} - 0.0001") OutAmount=${OutAmount/#./0.}
    RawInputs="${RawInputs::-1}]"
    RawOutputs="{\"${Addy}\": \"${OutAmount}\"}"
}
function addnlocktime() {
    nlocktime=$(printf "%08x" $(date +%s) | dd conv=swab 2>/dev/null | rev)
    chophex=$(sed 's/.\{38\}$//' <<<"${toSign}")
    nExpiryHeight=$(grep -o '.\{30\}$' <<<"${toSign}")
    newhex=${chophex}${nlocktime}${nExpiryHeight}
}

if [[ $enabled == "y" ]]; then
    LoopsCount=$(bc <<<"scale=0; (${UTXOcount} / ${maxInc})")
    echo "This will take $((${LoopsCount} + 1)) transaction(s) to complete...."
    SECONDS=0
    for txid in $(jq -r '.[].txid' <<<"${inputUTXOs}"); do txids+=("${txid}"); done
    echo "Captured txids..."
    for vout in $(jq -r '.[].vout' <<<"${inputUTXOs}"); do vouts+=("${vout}"); done
    echo "Captured vouts..."
    for amount in $(jq -r '.[].amount' <<<"${inputUTXOs}"); do
        if [[ "${amount}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            amounts+=("${amount}")
        else
            amounts+=("$(printf "%.8f" ${amount})")
        fi
    done
    duration=$SECONDS
    echo "Captured amounts... $(($duration % 60)) seconds"
    echo "Packed and ready to begin...."
    for ((tlc = 0; tlc <= ${LoopsCount}; tlc++)); do
	(( ${LoopsCount} > 1 )) && echo "${#vouts[@]} UTXOs left to consolitate..." || echo "${#vouts[@]} UTXOs to consolitate...";
        SECONDS=0
        if [[ ${#vouts[@]} -ge ${maxInc} ]]; then
            makeRaw ${maxInc}
        else
            makeRaw ${#vouts[@]}
        fi
        duration=$SECONDS
        echo "Created raw consolidated tx $(($duration % 60)) seconds"
        SECONDS=0
        toSign=$(komodo-cli${AssetChain} createrawtransaction "${RawInputs}" "${RawOutputs}" 2>/dev/null)
	status=$?
	if [ $status -eq 0 ]; then
		addnlocktime
		Signed=$(jq -r '.hex' <<<"$(komodo-cli${AssetChain} signrawtransaction $newhex)")
		lasttx=$(komodo-cli ${AssetChain} -stdin sendrawtransaction <<<"${Signed}")
		echo "Consolidated $(jq '. | length' <<<"${RawInputs}") UTXOs:"
		duration=$SECONDS
		echo "Sent signed raw consolidated tx: ${lasttx} for ${OutAmount} $ac_name  $(($duration % 60)) seconds"
		waitforconfirm ${lasttx}
	else
		: #echo "error caught ${RawInputs}"
	fi
	txids=("${txids[@]:${maxInc}}")
	vouts=("${vouts[@]:${maxInc}}")
	amounts=("${amounts[@]:${maxInc}}")
	RawInputs="[" OutAmount="0"
    done
else
    echo "$(jq <<<"${inputUTXOs}")"
    exit 1
fi
exit 0
