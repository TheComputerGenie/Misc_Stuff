#!/bin/bash
# Adopted from "Split NN script by Decker"
# uses blockchair.com to estimate the best fee to use, to count the mempool, and to show the USD value of BTC
# uses chain.so to get UTXOs

NN_ADDRESS=LYkPqWDBymF5ZgKb2dGS3Sayw5Hc9qnPsu                                # fill your NN address here
NN_PUBKEY=03f9dd0484e81174fd50775cb9099691c7d140ff00c0f088847e38dc87da67eb9b # fill your pubkey here
SPLIT_COUNT=78                                                               # more than 200-250 will impact node performance

NN_PUBKEY_SHA=$(xxd -r -p <<<"${NN_PUBKEY}" | sha256sum | awk '{print $1}')
NN_HASH160=$(xxd -r -p <<<"${NN_PUBKEY_SHA}" | openssl rmd160 | cut -c 10-)

function getchair() {
	chair=$(curl -s https://api.blockchair.com/litecoin/stats)
	chairfee=$(jq -r '.data.suggested_transaction_fee_per_byte_sat' <<<"${chair}")
	inpool=$(jq -r '.data.mempool_transactions' <<<"${chair}")
	USD=$(jq -r '.data.market_price_usd' <<<"${chair}")
	TXFEE_SATOSHI_BYTE=$(bc <<<"${chairfee} + 1")
}
getchair
if [[ $TXFEE_SATOSHI_BYTE -gt 22 ]]; then
	while [[ $TXFEE_SATOSHI_BYTE -gt 22 ]]; do
		echo "Fees too high now: ${TXFEE_SATOSHI_BYTE}"
		sleep 90
		getchair
	done
fi
echo "There are currently ${inpool} txes in the mempool"
echo "LTC/USD: ${USD}"
echo "Our fee(per byte): ${TXFEE_SATOSHI_BYTE}"

#UTXOs=$(curl -s https://chain.so/api/v2/get_tx_unspent/LTC/${NN_ADDRESS}|jq '.data.txs|[map(select(( (.value|tonumber) != 0.00010000)))| .[] | {txid, output_no, value,script_hex}]')
UTXOs=$(curl -s "https://api.blockcypher.com/v1/ltc/main/addrs/${NN_ADDRESS}?unspentOnly=true&includeScript=true" | jq '.txrefs|[map(select(( (.value|tonumber) != 0.00010000)))| .[] | {tx_hash, tx_output_n, value, script}]')
SPLIT_VALUE=0.0001
COINAGE_TOTAL=0
SPLIT_VALUE_SATOSHI=$(bc <<<"${SPLIT_VALUE}*100000000")
SPLIT_VALUE_SATOSHI=("$(printf "%.0f" ${SPLIT_VALUE_SATOSHI})")
SPLIT_TOTAL=$(bc <<<"${SPLIT_VALUE}*${SPLIT_COUNT}")
SPLIT_TOTAL_SATOSHI=$(bc <<<"${SPLIT_VALUE}*${SPLIT_COUNT}*100000000")
SPLIT_TOTAL_SATOSHI=("$(printf "%.0f" ${SPLIT_TOTAL_SATOSHI})")

if [[ $UTXOs != "null" ]]; then
	for txid in $(jq -r '.[].tx_hash' <<<"${UTXOs}"); do txids+=("$txid"); done
	for vin in $(jq -r '.[].tx_output_n' <<<"${UTXOs}"); do vins+=("$vin"); done
	for amount in $(jq -r '.[].value' <<<"${UTXOs}"); do
		COINAGE_TOTAL=$(bc <<< "scale=8;${COINAGE_TOTAL}+(${amount}*0.00000001)")
		COINAGE_TOTAL=${COINAGE_TOTAL/#./0.}
	done
	COINAGE_TOTAL_SATOSHI=$(bc <<<"scale=0;${COINAGE_TOTAL}*100000000")
	echo "Coinage total: ${COINAGE_TOTAL/#./0.} ($"$(bc <<<"scale=2;${COINAGE_TOTAL}*${USD}")")"
	for script in $(jq -r '.[].script_hex' <<<"${UTXOs}"); do scripts+=("$script"); done
	TOTAL_INS=${#vins[@]}
	TOTAL_UTXOs=$(bc <<<"${TOTAL_INS} + ${SPLIT_COUNT}")
	if [[ $TOTAL_UTXOs -gt 252 ]]; then
		SPLIT_COUNT=$(bc <<<"252 - ${TOTAL_INS}") # if too many, we correct to max for less fail
	fi
	rawtx="02000000"                             # tx version
	rawtx="${rawtx}$(printf "%02x" ${#vins[@]})" # number of inputs
	for ((tc = 0; tc <= ${TOTAL_INS} - 1; tc++)); do
		vin_hex=$(printf "%08x" ${vins[tc]} | dd conv=swab 2>/dev/null | rev)
		rev_txid=$(dd conv=swab 2>/dev/null <<<"${txids[tc]}" | rev)
		rawtx="${rawtx}${rev_txid}${vin_hex}00ffffffff" # formatted txid, which vout it was, and signature placeholder
	done

	oc=$((SPLIT_COUNT + 1))
	outputCount=$(printf "%02x" $oc)
	rawtx=${rawtx}${outputCount}
	rawtxsize=$(($(wc -m <<<${rawtx}) / 2))                                     # 2 chrs = 1 byte
	rawtxsize=$(((rawtxsize + (${TOTAL_INS} * 107) + (SPLIT_COUNT * 44) + 38))) # inputs size + signatures + outputs size((8 + 1 + 35) each) + change size(8 + 1 + 25) + nLockTime (4)
	echo "Estimated TX size: ${rawtxsize}"
	echo "New notary UTXOs: ${SPLIT_COUNT}"
	for ((i = 1; i <= $SPLIT_COUNT; i++)); do
		value=$(printf "%016x" ${SPLIT_VALUE_SATOSHI} | dd conv=swab 2>/dev/null | rev)
		rawtx="${rawtx}${value}2321${NN_PUBKEY}ac" # adding vout amount and OP codes
	done

	TOTAL_FEE_SATOSHI=$((${rawtxsize} * ${TXFEE_SATOSHI_BYTE}))
	TOTAL_FEE=$(bc <<<"scale=8;${TOTAL_FEE_SATOSHI}/100000000")
	echo "TOTAL_FEE: ${TOTAL_FEE/#./0.} ($"$(bc <<<"scale=2;${TOTAL_FEE}*${USD}")")"
	change_satoshis=$(bc <<<"${COINAGE_TOTAL_SATOSHI}-${SPLIT_TOTAL_SATOSHI}-${TOTAL_FEE_SATOSHI}")
	change_satoshis=${change_satoshis%.*}
	change=$(bc <<<"scale=8;${change_satoshis}/100000000")
	echo "Change: ${change/#./0.}"

	value=$(printf "%016x" ${change_satoshis} | dd conv=swab 2>/dev/null | rev)
	rawtx="${rawtx}${value}1976a914${NN_HASH160}88ac00000000" # adding change amount and OP codes and for BTC nLockTime is 0 (!)
	Signed=$(litecoin-cli -stdin signrawtransaction <<<${rawtx} | jq -r '.hex')
	lasttx=$(litecoin-cli -stdin sendrawtransaction <<<${Signed})
	echo -e "\033[33mSplit TX: ${lasttx}\033[0m"
	echo -e "\n"
	exit 0
else
	echo -e "ERROR!\n Nothing to split ... :("
	exit 1
fi
