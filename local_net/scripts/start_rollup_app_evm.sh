#!/bin/sh

###init params
whoami
tmp=$(mktemp)
export ROLLAPP_CHAIN_ID="rollappevm_1234-1"
export KEY_NAME_ROLLAPP="roluser"
#export DENOM="urax"
export MONIKER="rolmoniker"
EXECUTABLE="rollappd"
ROLLAPP_CHAIN_DIR="$HOME/.rollapp_evm"

#export EXECUTABLE="rollapp-evm"
export BECH32_PREFIX="ethm"
#export ROLLAPP_CHAIN_ID="rollappevm_1234-1"
#export KEY_NAME_ROLLAPP="rol-user"
export BASE_DENOM="arax"
export DENOM=$(echo "$BASE_DENOM" | sed 's/^.//')
export MONIKER="$ROLLAPP_CHAIN_ID-sequencer"

export ROLLAPP_HOME_DIR="$HOME/.rollapp_evm"
export ROLLAPP_SETTLEMENT_INIT_DIR_PATH="${ROLLAPP_HOME_DIR}/init"
export SKIP_EVM_BASE_FEE=true # optional, removes fees on the rollapp


# ---------------------------- initial parameters ---------------------------- #
# Assuming 1,000,000 tokens
# Half is staked
# set BASE_DENOM to the token denomination
TOKEN_AMOUNT="1000000000000000000000000$BASE_DENOM"
STAKING_AMOUNT="500000000000000000000000$BASE_DENOM"

CONFIG_DIRECTORY="$ROLLAPP_HOME_DIR/config"
GENESIS_FILE="$CONFIG_DIRECTORY/genesis.json"
DYMINT_CONFIG_FILE="$CONFIG_DIRECTORY/dymint.toml"
APP_CONFIG_FILE="$CONFIG_DIRECTORY/app.toml"



set_denom() {
  local denom=$1
  local success=true

  jq --arg denom "$denom" '.app_state.mint.params.mint_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE" ||
    success=false
  jq --arg denom "$denom" '.app_state.staking.params.bond_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE" ||
    success=false
  jq --arg denom "$denom" '.app_state.gov.deposit_params.min_deposit[0].denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE" ||
    success=false
  jq --arg denom "$denom" '.app_state.evm.params.evm_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE" ||
    success=false
  jq --arg denom "$denom" '.app_state.claims.params.claims_denom = $denom' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE" ||
    success=false

  if [ "$success" = false ]; then
    echo "An error occurred. Please refer to README.md"
    return 1
  fi
}

set_consensus_params() {
  BLOCK_SIZE="500000"
  jq --arg block_size "$BLOCK_SIZE" '.consensus_params["block"]["max_bytes"] = $block_size' "$GENESIS_FILE" >"$tmp" && mv "$tmp" "$GENESIS_FILE"
  jq --arg block_size "$BLOCK_SIZE" '.consensus_params["evidence"]["max_bytes"] = $block_size' "$GENESIS_FILE" >"$tmp" && mv "$tmp" "$GENESIS_FILE"
  jq '.consensus_params["block"]["max_gas"] = "400000000"' "$GENESIS_FILE" >"$tmp" && mv "$tmp" "$GENESIS_FILE"
}

SKIP_BASE_FEE=${SKIP_EVM_BASE_FEE-false}

set_EVM_params() {
  jq --arg skip "$SKIP_BASE_FEE" '.app_state["feemarket"]["params"]["no_base_fee"] = ($skip == "true")' "$GENESIS_FILE" >"$tmp" && mv "$tmp" "$GENESIS_FILE"
  jq '.app_state["feemarket"]["params"]["min_gas_price"] = "10000000.0"' "$GENESIS_FILE" >"$tmp" && mv "$tmp" "$GENESIS_FILE"
}

init(){
# --------------------------------- run init --------------------------------- #
if ! command -v "$EXECUTABLE" >/dev/null; then
  echo "$EXECUTABLE does not exist"
  echo "please run make install"
  exit 1
fi

if [ "$ROLLAPP_CHAIN_ID" = "" ]; then
  echo "ROLLAPP_CHAIN_ID is not set"
  exit 1
fi

# Verify that a genesis file doesn't exists for the dymension chain
if [ -f "$GENESIS_FILE" ]; then
  printf "\n======================================================================================================\n"
  echo "A genesis file already exists at $GENESIS_FILE."
  echo "Building the chain will delete all previous chain data. Continue? (y/n)"
  printf "\n======================================================================================================\n"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    rm -rf "$ROLLAPP_HOME_DIR"
  else
    exit 1
  fi
fi

# Check if MONIKER is set, if not, set a default value
if [ -z "$MONIKER" ]; then
    MONIKER="${ROLLAPP_CHAIN_ID}-sequencer" # Default moniker value
fi

# Check if KEY_NAME_ROLLAPP is set, if not, set a default value
if [ -z "$KEY_NAME_ROLLAPP" ]; then
    KEY_NAME_ROLLAPP="rol-user" # Default key name value
fi

# ------------------------------- init rollapp ------------------------------- #
"$EXECUTABLE" init "$MONIKER" --chain-id "$ROLLAPP_CHAIN_ID"

# ------------------------------- client config ------------------------------ #
"$EXECUTABLE" config chain-id "$ROLLAPP_CHAIN_ID"

# -------------------------------- app config -------------------------------- #
# Detect the operating system
OS=$(uname)

# Modify app.toml minimum-gas-prices using sed command based on the OS
if [ "$OS" = "Darwin" ]; then
    # macOS requires an empty string '' after -i to edit in place without backup
    sed -i '' "s/^minimum-gas-prices *= .*/minimum-gas-prices = \"0$BASE_DENOM\"/" "$APP_CONFIG_FILE"
else
    # Linux directly uses -i for in-place editing without creating a backup
    sed -i "s/^minimum-gas-prices *= .*/minimum-gas-prices = \"0$BASE_DENOM\"/" "$APP_CONFIG_FILE"
fi
set_denom "$BASE_DENOM"
set_consensus_params
set_EVM_params

# --------------------- adding keys and genesis accounts --------------------- #
# Local genesis account
"$EXECUTABLE" keys add "$KEY_NAME_ROLLAPP" --keyring-backend test
"$EXECUTABLE" add-genesis-account "$KEY_NAME_ROLLAPP" "$TOKEN_AMOUNT" --keyring-backend test

# Set sequencer's operator address
operator_address=$("$EXECUTABLE" keys show "$KEY_NAME_ROLLAPP" -a --keyring-backend test --bech val)
jq --arg addr "$operator_address" '.app_state["sequencers"]["genesis_operator_address"] = $addr' "$GENESIS_FILE" > "$tmp" && mv "$tmp" "$GENESIS_FILE"


# Ask if to include a governor on genesis

  "$EXECUTABLE" gentx "$KEY_NAME_ROLLAPP" "$STAKING_AMOUNT" --chain-id "$ROLLAPP_CHAIN_ID" --keyring-backend test --home "$ROLLAPP_HOME_DIR" --fees 4000000000000$BASE_DENOM
  "$EXECUTABLE" collect-gentxs --home "$ROLLAPP_HOME_DIR"


"$EXECUTABLE" validate-genesis
}

# Verify that a genesis file doesn't exists for the rollup app
if [ -f "$GENESIS_FILE" ]; then
  printf "\n======================================================================================================\n"
  echo "A genesis file already exists."
  rollappd start
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
        sleep 3s
    done
    mkdir -p "$ROLLAPP_CHAIN_DIR"/sequencer_keys
    cp -r /dymension_home/keyring-test "$ROLLAPP_CHAIN_DIR"/sequencer_keys/keyring-test

    "$EXECUTABLE" validate-genesis
    rollappd start
fi


