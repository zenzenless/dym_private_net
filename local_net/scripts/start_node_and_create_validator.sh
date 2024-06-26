#!/bin/bash

# This script starts a Celestia-app, creates a validator with the provided parameters, then
# keeps running it validating blocks.

# check if environment variables are set
if [[ -z "${CELESTIA_HOME}" || -z "${MONIKER}" || -z "${AMOUNT}" ]]
then
  echo "Environment not setup correctly. Please set: CELESTIA_HOME, MONIKER, AMOUNT variables"
  exit 1
fi

# create necessary structure if doesn't exist
if [[ ! -f ${CELESTIA_HOME}/data/priv_validator_state.json ]]
then
    mkdir "${CELESTIA_HOME}"/data
    cat <<EOF > ${CELESTIA_HOME}/data/priv_validator_state.json
{
  "height": "0",
  "round": 0,
  "step": 0
}
EOF
fi

apk update && apk add --no-cache curl jq
 # wait for the node to get up and running
# while true
# do
#   status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null core0:26657/status)
#   if [[ "${status_code}" -eq 200 ]] ; then
#     break
#   fi
#   echo "Waiting for node to be up..."
#   sleep 2s
# done


echo "Initialize a working directory"
CHAIN_ID="private"
celestia-appd init $MONIKER --chain-id $CHAIN_ID --home "${CELESTIA_HOME}"
echo "cp file"
cp -r /core0_shared/keyring-test "${CELESTIA_HOME}"/keyring-test

cp /core0_shared/config/*.toml "${CELESTIA_HOME}"/config/
ls -al "${CELESTIA_HOME}"/config/
cp /core0_shared/config/genesis.json "${CELESTIA_HOME}"/config/genesis.json
ls /core0_shared/
{
  # wait for the node to get up and running
  while true
  do
    status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null localhost:26657/status)
    if [[ "${status_code}" -eq 200 ]] ; then
      break
    fi
    echo "Waiting for node to be up..."
    sleep 2s
  done

  
  VAL_ADDRESS=$(celestia-appd keys show "${MONIKER}" --keyring-backend test --bech=val --home "${CELESTIA_HOME}" -a)

  
  
  # keep retrying to create a validator
  while true
  do
    # create validator
    celestia-appd tx staking create-validator \
      --amount="${AMOUNT}" \
      --pubkey="$(celestia-appd tendermint show-validator --home "${CELESTIA_HOME}")" \
      --moniker="${MONIKER}" \
      --chain-id="private" \
      --commission-rate=0.1 \
      --commission-max-rate=0.2 \
      --commission-max-change-rate=0.01 \
      --min-self-delegation=1000000 \
      --from="${MONIKER}" \
      --keyring-backend=test \
      --home="${CELESTIA_HOME}" \
      --broadcast-mode=block \
      --fees="300000utia" \
      --yes
    output=$(celestia-appd query staking validator "${VAL_ADDRESS}" 2>/dev/null)
    if [[ -n "${output}" ]] ; then
      break
    fi
    echo "trying to create validator..."
    sleep 1s
  done
} &

# start node

celestia-appd start \
--home="${CELESTIA_HOME}" \
--moniker="${MONIKER}" \
--p2p.persistent_peers=`cat /core0_shared/node-id`@core0:26656 \
--rpc.laddr=tcp://0.0.0.0:26657 \
--grpc.enable true
 