# Get Start

run command

``` sh
git clone git@github.com:st-chain/private_net.git
cd private_net
git submodule init
git submodule update
cd local_net

#Run containers in the background
docker-compose up -d
docker-compose logs -f
```