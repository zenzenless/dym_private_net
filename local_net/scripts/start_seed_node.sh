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
echo "exit 1" > /var/ok.sh
#apk update && apk add --no-cache curl jq
# wait for the node to get up and running
while true
do
  status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null core0:26657/status)
  if [[ "${status_code}" -eq 200 ]] ; then
    break
  fi
  echo "Waiting for node to be up..."
  sleep 2s
done


echo "Initialize a working directory"
CHAIN_ID="private"
celestia-appd init $MONIKER --chain-id $CHAIN_ID --home "${CELESTIA_HOME}"
echo "cp file"
cp -r /core0_shared/keyring-test "${CELESTIA_HOME}"/keyring-test

cp /core0_shared/config/*.toml "${CELESTIA_HOME}"/config/
ls -al "${CELESTIA_HOME}"/config/
cp /core0_shared/config/genesis.json "${CELESTIA_HOME}"/config/genesis.json
ls /core0_shared/





sleep 2s
# wait for the node to get up and running
{
    while true
    do
      status_code=$(curl --write-out '%{http_code}' --silent --output /dev/null localhost:26657/status)
      if [[ "${status_code}" -eq 200 ]] ; then
        break
      fi
      echo "Waiting for node to be up..."
      sleep 2s
    done

    id=`celestia-appd tendermint show-node-id --home=${CELESTIA_HOME}`
    seeds=$id@seed0:26656
    sed -i "s/seeds = \"\"/seeds = \"${seeds}\"/g" /core0_shared/config/config.toml

    core0_peer=`cat /core0_shared/node-id`@core0:26656
    sed -i "s/persistent_peers = \"\"/persistent_peers = \"${seeds},${core0_peer}\"/g" /core0_shared/config/config.toml
    cat /core0_shared/config/config.toml
    echo "exit 0" > /var/ok.sh
}&


# start node
celestia-appd start \
--home="${CELESTIA_HOME}" \
--moniker="${MONIKER}" \
--p2p.seed_mode=true \
--rpc.laddr=tcp://0.0.0.0:26657 \
--grpc.enable true