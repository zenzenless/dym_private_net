#!/bin/bash

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
echo "exit 1" > /var/ok.sh
hash=""
while true
do
    hash=`curl "core0:26657/block?height=1" |jq .result.block_id.hash`
    if [[ ${hash} != "null" ]] ; then
        break
    fi
    sleep 2s

done


celestia ${NODE_TYPE} init --p2p.network private

echo hash $hash
sed -i "s/TrustedHash = \"\"/TrustedHash = ${hash}/" /home/celestia/.celestia-${NODE_TYPE}-private/config.toml
sed -i "s/SkipAuth = false/SkipAuth = true/" /home/celestia/.celestia-${NODE_TYPE}-private/config.toml

if [[ $NODE_TYPE == "bridge" ]] ;then
#save peers
{   
    peers_id=""
    while true
    do
        peers_id=`celestia p2p info |jq -r '.result.id'`
        if [[ $peers_id != "" ]] ; then
            break
        fi
        echo "Waitinnnnnnnnnnnnnnnnnnnnnng for peers to be up..."
        sleep 2s
    done
    IP=$(cat /etc/hosts |grep `cat /etc/hostname` |grep -E '\d+\.\d+\.\d+\.\d+' -o)
    peers="/ip4/${IP}/tcp/2121/p2p/$peers_id"
    echo "peers are $peers"
    echo $peers > /home/celestia/peer.info
    echo "exit 0" > /var/ok.sh
    # echo "peers are $peers"
    # if [ $NODE_TYPE != "bridge" ]
    # then
    #     echo "sed celestia light node or full node config.toml"
    #     peers=`cat /peer/peer.info`
    #     sed -i "s/TrustedPeers = []/TrustedPeers = ${peers}/" /home/celestia/.celestia-${NODE_TYPE}-private/config.toml
    # else
    #     echo "save peer info"
    #     celestia p2p info |jq '.result.peer_addr' > /peer/peer.info
    # fi
}&
fi

if [[ $NODE_TYPE != "bridge" ]] ;then
    #write peers
    
    # 读取并转义 peers 内容
    peers=$(sed 's/[]\/$*.^[]/\\&/g' /home/celestia/peer.info)

    # 输出调试信息
    echo "write peers :$peers"
    sed -i "s/TrustedPeers = \[\]/TrustedPeers = \[\"${peers}\"\]/" /home/celestia/.celestia-${NODE_TYPE}-private/config.toml
fi

cat /home/celestia/.celestia-${NODE_TYPE}-private/config.toml
echo "cp file"
cp  /core0_shared/keyring-test/* /home/celestia/.celestia-${NODE_TYPE}-private/keys/keyring-test
celestia ${NODE_TYPE} start --core.ip core0 --core.rpc.port 26657 --core.grpc.port 9090 --p2p.network private --keyring.accname ${NODE_TYPE}