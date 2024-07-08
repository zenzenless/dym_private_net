#!/bin/sh

###init params
whoami
tmp=$(mktemp)
export ROLLAPP_CHAIN_ID="rollappevm_1234-1"
export KEY_NAME_ROLLAPP="roluser"
export DENOM="urax"
export MONIKER="rolmoniker"
EXECUTABLE="rollappd"
ROLLAPP_CHAIN_DIR="$HOME/.rollapp"

set_denom() {
  denom=$1
  jq --arg denom $denom '.app_state.mint.params.mint_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE"
  jq --arg denom $denom '.app_state.staking.params.bond_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE"
  jq --arg denom $denom '.app_state.gov.deposit_params.min_deposit[0].denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE"
}

# ---------------------------- initial parameters ---------------------------- #
# Assuming 1,000,000 tokens
#half is staked
TOKEN_AMOUNT="1000000000000$DENOM"
STAKING_AMOUNT="500000000000$DENOM"


CONFIG_DIRECTORY="$ROLLAPP_CHAIN_DIR/config"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"
TENDERMINT_CONFIG_FILE="$CONFIG_DIRECTORY/config.toml"
APP_CONFIG_FILE="$CONFIG_DIRECTORY/app.toml"



init(){
# --------------------------------- run init --------------------------------- #
if ! command -v $EXECUTABLE >/dev/null; then
  echo "$EXECUTABLE does not exist"
  echo "please run make install"
  exit 1
fi

if [ -z "$ROLLAPP_CHAIN_ID" ]; then
  echo "ROLLAPP_CHAIN_ID is not set"
  exit 1
fi

# Verify that a genesis file doesn't exists for the dymension chain
if [ -f "$GENESIS_FILE" ]; then
  printf "\n======================================================================================================\n"
  echo "A genesis file already exists [$GENESIS_FILE]. building the chain will delete all previous chain data. continue? (y/n)"
  printf "\n======================================================================================================\n"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    rm -rf "$ROLLAPP_CHAIN_DIR"
  else
    exit 1
  fi
fi

# ------------------------------- init rollapp ------------------------------- #
$EXECUTABLE init "$MONIKER" --chain-id "$ROLLAPP_CHAIN_ID"

# ------------------------------- client config ------------------------------ #
$EXECUTABLE config keyring-backend test
$EXECUTABLE config chain-id "$ROLLAPP_CHAIN_ID"

# -------------------------------- app config -------------------------------- #
sed -i'' -e "s/^minimum-gas-prices *= .*/minimum-gas-prices = \"0$DENOM\"/" "$APP_CONFIG_FILE"
set_denom "$DENOM"

# --------------------- adding keys and genesis accounts --------------------- #
#local genesis account
$EXECUTABLE keys add "$KEY_NAME_ROLLAPP" --keyring-backend test
$EXECUTABLE add-genesis-account "$KEY_NAME_ROLLAPP" "$TOKEN_AMOUNT" --keyring-backend test
$EXECUTABLE gentx_seq --pubkey "$($EXECUTABLE dymint show-sequencer)" --from "$KEY_NAME_ROLLAPP"


$EXECUTABLE gentx "$KEY_NAME_ROLLAPP" "$STAKING_AMOUNT" --chain-id "$ROLLAPP_CHAIN_ID" --keyring-backend test --home "$ROLLAPP_CHAIN_DIR"
$EXECUTABLE collect-gentxs --home "$ROLLAPP_CHAIN_DIR"


$EXECUTABLE validate-genesis




}

# Verify that a genesis file doesn't exists for the rollup app
if [ -f "$GENESIS_FILE" ]; then
  printf "\n======================================================================================================\n"
  echo "A genesis file already exists."
  dlv --headless=true --listen=:23456 --log --api-version=2 exec --continue /bin/rollappd start
else
    echo "start init rollup app"
    init
    sed -i "s/settlement_layer = \"mock\"/settlement_layer = \"dymension\"/" ${CONFIG_DIRECTORY}/dymint.toml
    sed -i "s/settlement_node_address = \"http:\/\/127.0.0.1:36657\"/settlement_node_address = \"http:\/\/dymension:36657\"/" ${CONFIG_DIRECTORY}/dymint.toml

    sed -i "s/da_layer = \"mock\"/da_layer = \"celestia\"/" ${CONFIG_DIRECTORY}/dymint.toml
    

    # 读取 JSON 数据
    json_data='{
      "base_url": "http://light_node:26658",
      "timeout": 5000000000,
      "gas_prices": 0.1,
      "auth_token": "TOKEN",
      "backoff": {
        "initial_delay": 6000000000,
        "max_delay": 6000000000,
        "growth_factor": 2
      },
      "retry_attempts": 4,
      "retry_delay": 3000000000
    }'
    escaped_json=$(echo "$json_data" | jq -c .| sed 's/"/\\"/g')


    # 使用 sed 替换 TOML 文件中的 da_config 字段
    sed -i "s|da_config = \"\"|da_config = \'$escaped_json\'|" ${CONFIG_DIRECTORY}/dymint.toml


    rollappd dymint show-sequencer > "$ROLLAPP_CHAIN_DIR"/sequencer.info
    echo "exit 0" > "$ROLLAPP_CHAIN_DIR"/init_done.sh
    # waiting for create sequencer
    while true
    do
        bash /dymension_home/dymd_ok.sh >/dev/null 2>&1 && break
        echo "wait for dymension init ..."
        sleep 3s
    done
    mkdir -p "$ROLLAPP_CHAIN_DIR"/sequencer_keys
    cp -r /dymension_home/keyring-test "$ROLLAPP_CHAIN_DIR"/sequencer_keys/keyring-test
    dlv --headless=true --listen=:23456 --log --api-version=2 exec --continue /bin/rollappd start
fi


