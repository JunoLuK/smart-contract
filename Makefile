include .env
export

install:
	forge install

build:
	forge build

test:
	forge test

local-network:
	anvil

watch-coverage:
	mkdir -p coverage
	forge coverage --report lcov
	genhtml lcov.info --branch-coverage --output-dir coverage
	open coverage/index.html

# deploy to with aws signer
deploy:
	forge script script/AKDD.s.sol --rpc-url ${RPC_URL} --aws --broadcast -vvvv --sender ${SENDER_WALLET_ADDRESS}

# grants minter permissions
grant-minter:
	forge script script/grantMinter.s.sol --rpc-url ${RPC_URL} --aws --broadcast -vvvv --sender ${SENDER_WALLET_ADDRESS}

# grants minter permissions
grant-transferrer:
	forge script script/grantTransferrer.s.sol --rpc-url ${RPC_URL} --aws --broadcast -vvvv --sender ${SENDER_WALLET_ADDRESS}

mint:
	forge script script/mint.s.sol --rpc-url ${RPC_URL} --aws --broadcast -vvvv --sender ${SENDER_WALLET_ADDRESS}

transfer:
	forge script script/transfer.s.sol --rpc-url ${RPC_URL} --aws --broadcast -vvvv --sender ${SENDER_WALLET_ADDRESS}

abigen-go-bindings:
	mkdir -p abigenBindings/abi
	cat out/AKDD.sol/AKDD.json | jq ".abi" > abigenBindings/abi/AKDD.abi
	abigen --abi abigenBindings/abi/AKDD.abi --pkg contract --out ../back/transactions/internal/pkg/ethereum/contract/akdd.go
	abigen --abi=abigenBindings/abi/AKDD.abi --pkg=contract --out=../back/transactions-event-proxy/internal/pkg/ethereum/contract/akdd.go
