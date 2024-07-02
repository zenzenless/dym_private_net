#!/bin/sh

# Common commands
genesis_config_cmds="/app/scripts/genesis_config_commands.sh"
. "$genesis_config_cmds"

# Set parameters
DATA_DIRECTORY="$HOME/.dymension"
CONFIG_DIRECTORY="$DATA_DIRECTORY/config"
TENDERMINT_CONFIG_FILE="$CONFIG_DIRECTORY/config.toml"
CLIENT_CONFIG_FILE="$CONFIG_DIRECTORY/client.toml"
APP_CONFIG_FILE="$CONFIG_DIRECTORY/app.toml"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"
CHAIN_ID=${CHAIN_ID:-"dymension_100-1"}
MONIKER_NAME=${MONIKER_NAME:-"local"}
KEY_NAME=${KEY_NAME:-"local-user"}

# Setting non-default ports to avoid port conflicts when running local rollapp
SETTLEMENT_ADDR=${SETTLEMENT_ADDR:-"0.0.0.0:36657"}
P2P_ADDRESS=${P2P_ADDRESS:-"0.0.0.0:36656"}
GRPC_ADDRESS=${GRPC_ADDRESS:-"0.0.0.0:8090"}
GRPC_WEB_ADDRESS=${GRPC_WEB_ADDRESS:-"0.0.0.0:8091"}
API_ADDRESS=${API_ADDRESS:-"0.0.0.0:1318"}
JSONRPC_ADDRESS=${JSONRPC_ADDRESS:-"0.0.0.0:9545"}
JSONRPC_WS_ADDRESS=${JSONRPC_WS_ADDRESS:-"0.0.0.0:9547"}

TOKEN_AMOUNT=${TOKEN_AMOUNT:-"1000000000000000000000000adym"} #1M DYM (1e6dym = 1e6 * 1e18 = 1e24adym )
STAKING_AMOUNT=${STAKING_AMOUNT:-"670000000000000000000000adym"} #67% is staked (inflation goal)

init(){
# Validate dymension binary exists
export PATH=$PATH:$HOME/go/bin
if ! command -v dymd > /dev/null; then
  make install
  if ! command -v dymd; then
    echo "dymension binary not found in $PATH"
    exit 1
  fi
fi

# Create and init dymension chain
dymd init "$MONIKER_NAME" --chain-id="$CHAIN_ID"

# ---------------------------------------------------------------------------- #
#                              Set configurations                              #
# ---------------------------------------------------------------------------- #
sed -i'' -e "/\[rpc\]/,+3 s/laddr *= .*/laddr = \"tcp:\/\/$SETTLEMENT_ADDR\"/" "$TENDERMINT_CONFIG_FILE"
sed -i'' -e "/\[p2p\]/,+3 s/laddr *= .*/laddr = \"tcp:\/\/$P2P_ADDRESS\"/" "$TENDERMINT_CONFIG_FILE"

sed -i'' -e "/\[grpc\]/,+6 s/address *= .*/address = \"$GRPC_ADDRESS\"/" "$APP_CONFIG_FILE"
sed -i'' -e "/\[grpc-web\]/,+7 s/address *= .*/address = \"$GRPC_WEB_ADDRESS\"/" "$APP_CONFIG_FILE"
sed -i'' -e "/\[json-rpc\]/,+6 s/address *= .*/address = \"$JSONRPC_ADDRESS\"/" "$APP_CONFIG_FILE"
sed -i'' -e "/\[json-rpc\]/,+9 s/ws-address *= .*/ws-address = \"$JSONRPC_WS_ADDRESS\"/" "$APP_CONFIG_FILE"
sed -i'' -e '/\[api\]/,+3 s/enable *= .*/enable = true/' "$APP_CONFIG_FILE"
sed -i'' -e "/\[api\]/,+9 s/address *= .*/address = \"tcp:\/\/$API_ADDRESS\"/" "$APP_CONFIG_FILE"

sed -i'' -e 's/^minimum-gas-prices *= .*/minimum-gas-prices = "0adym"/' "$APP_CONFIG_FILE"

sed -i'' -e "s/^chain-id *= .*/chain-id = \"$CHAIN_ID\"/" "$CLIENT_CONFIG_FILE"
sed -i'' -e "s/^keyring-backend *= .*/keyring-backend = \"test\"/" "$CLIENT_CONFIG_FILE"
sed -i'' -e "s/^node *= .*/node = \"tcp:\/\/$SETTLEMENT_ADDR\"/" "$CLIENT_CONFIG_FILE"

set_consenus_params
set_gov_params
set_hub_params
set_misc_params
set_EVM_params
set_bank_denom_metadata
set_epochs_params
set_incentives_params

dymd keys add "$KEY_NAME" --keyring-backend test 
dymd keys add sequencer --keyring-backend test 


dymd add-genesis-account "$(dymd keys show "$KEY_NAME" -a --keyring-backend test)" "$TOKEN_AMOUNT"
#dymd add-genesis-account "$(dymd keys show sequencer -a --keyring-backend test)" "$TOKEN_AMOUNT"

dymd gentx "$KEY_NAME" "$STAKING_AMOUNT" --chain-id "$CHAIN_ID" --keyring-backend test
dymd collect-gentxs



}

create_rollapp(){
{

  while true
  do
    status_code=$(dymd status 2> /dev/null)
    if [[ -n "${status_code}" ]] ; then
      break
    fi
    echo "Waiting for node to be up..."
    sleep 2s
  done    

  # give sequencer some money
  SEQUENCER_ADDR=`dymd keys show sequencer --address --keyring-backend test`
  while true
  do
    output=$(dymd query bank balances $SEQUENCER_ADDR)
    if [[ -n "${output}" ]] ; then
      echo "query bank balances success"
   
      output=$(dymd query bank balances $SEQUENCER_ADDR)
      if echo "$output" | grep -q 'balances: \[\]'; then
        echo "trying to give some money to sequencer..."
        sleep 1s
      else
        echo "give some money to sequencer success"
        break
      fi
    else
      sleep 1s
      continue
    fi
    
    dymd tx bank send $KEY_NAME $SEQUENCER_ADDR 10000000000000000000000adym \
    --keyring-backend test \
    --broadcast-mode block \
    --yes
  done



   # keep retrying to create a create-rollapp
  while true
  do
    output=$(dymd query rollapp show rollappevm_1234-1 2>/dev/null)
    if [[ -n "${output}" ]] ; then
      echo "create rollapp rollappevm_1234-1 success"
      break
    fi
    
    echo "trying to create rollapp..."
    sleep 1s    
    # create create-rollapp
    dymd tx rollapp create-rollapp rollappevm_1234-1 1 '{"Addresses":[]}' \
    --from ${KEY_NAME} \
    --keyring-backend test \
    --broadcast-mode block \
    --yes

  done

  while true
  do
    bash /rollup_app_home/init_done.sh > /dev/null && break
    echo "Waiting for rollup_app to be up..."
    sleep 2s
  done

  while true
  do
  # create-sequencer
    output=$(dymd query sequencer show-sequencers-by-rollapp rollappevm_1234-1)
    if echo "$output" | grep -q 'sequencers: \[\]'; then
      echo "trying to create sequencer..."
      sleep 1s
    else
      echo "create sequencer success"
      break
    fi
    
    dymd tx sequencer create-sequencer "$(cat /rollup_app_home/sequencer.info)" rollappevm_1234-1 "{\"Moniker\":\"rolmoniker\",\"Identity\":\"\",\"Website\":\"\",\"SecurityContact\":\"\",\"Details\":\"\"}" 1000000adym \
    --from sequencer \
    --keyring-backend test \
    --broadcast-mode block \
    --yes


    
  done

  echo "exit 0" >${DATA_DIRECTORY}/dymd_ok.sh
}&
}
# Verify that a genesis file doesn't exists for the dymension chain
if [ -f "$GENESIS_FILE" ]; then
  printf "\n======================================================================================================\n"
  echo "A genesis file already exists."
  dymd start
else
  echo "start init dymesion node"
  init
  create_rollapp
  dymd start
fi



#在dymension上创建rollapp（使用上文中的$ROLLAPP_CHAIN_ID）

#dymd tx rollapp create-rollapp rollappevm_1234-1 1 '{"Addresses":[]}' --from ${KEY_NAME} --keyring-backend test --broadcast-mode block --yes

#为rollapp添加sequencer
#dymd tx sequencer create-sequencer "$(rollappd dymint show-sequencer)" rollappevm_1234-1 "{\"Moniker\":\"rolmoniker\",\"Identity\":\"\",\"Website\":\"\",\"SecurityContact\":\"\",\"Details\":\"\"}" 1000000adym --from sequencer --keyring-dir ~/.rollapp/sequencer_keys --keyring-backend test --broadcast-mode block