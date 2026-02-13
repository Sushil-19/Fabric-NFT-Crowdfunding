#!/bin/bash

set -e

## Configuration
PROJECT_NAME="Fabric-Test-Network"
NETWORK_NAME="fabric-test-net" 
CHANNEL_NAME="mychannel"
CHAINCODE_NAME="basic-asset"
CHAINCODE_VERSION="1.0"
CHAINCODE_SEQUENCE="1"
CHAINCODE_LANG="node" 

# Organization details - UPDATED to Org1 and Org2 as per requirements
ORDERER_ORG="ordererOrg"
ORDERER_DOMAIN="orderer.example.com"
ORG1="org1"
ORG1_DOMAIN="org1.example.com"
ORG2="org2"
ORG2_DOMAIN="org2.example.com"

# CA admin credentials
CA_ADMIN_USER="admin"
CA_ADMIN_PASS="adminpw"

# Docker image versions
FABRIC_CA_IMAGE="hyperledger/fabric-ca:1.5.7"
FABRIC_ORDERER_IMAGE="hyperledger/fabric-orderer:2.5"
FABRIC_PEER_IMAGE="hyperledger/fabric-peer:2.5"
FABRIC_TOOLS_IMAGE="hyperledger/fabric-tools:2.5"
FABRIC_COUCHDB_IMAGE="hyperledger/fabric-couchdb:latest"
FABRIC_EXPLORER_IMAGE="hyperledger/explorer:latest"
FABRIC_EXPLORER_DB_IMAGE="hyperledger/explorer-db:latest"

## --- SECTION 1: CLEANUP AND DIRECTORY SETUP ---

echo "=================================================="
echo "SECTION 1: CLEANUP AND DIRECTORY SETUP"
echo "=================================================="

echo "Performing thorough cleanup of previous deployment..."
docker stop $(docker ps -a -q --filter ancestor="$FABRIC_CA_IMAGE" --filter ancestor="$FABRIC_ORDERER_IMAGE" --filter ancestor="$FABRIC_PEER_IMAGE" --filter ancestor="$FABRIC_TOOLS_IMAGE" --filter ancestor="$FABRIC_COUCHDB_IMAGE" --filter ancestor="$FABRIC_EXPLORER_IMAGE" --filter ancestor="$FABRIC_EXPLORER_DB_IMAGE" --filter name="ca-${ORG1}" --filter name="ca-${ORG2}" --filter name="orderer.${ORDERER_DOMAIN}" --filter name="peer0-${ORG1}" --filter name="peer0-${ORG2}" --filter name="cli" --filter name="explorer" --filter name="explorer-db") 2>/dev/null || true
docker rm $(docker ps -a -q --filter ancestor="$FABRIC_CA_IMAGE" --filter ancestor="$FABRIC_ORDERER_IMAGE" --filter ancestor="$FABRIC_PEER_IMAGE" --filter ancestor="$FABRIC_TOOLS_IMAGE" --filter ancestor="$FABRIC_COUCHDB_IMAGE" --filter ancestor="$FABRIC_EXPLORER_IMAGE" --filter ancestor="$FABRIC_EXPLORER_DB_IMAGE" --filter name="ca-${ORG1}" --filter name="ca-${ORG2}" --filter name="orderer.${ORDERER_DOMAIN}" --filter name="peer0-${ORG1}" --filter name="peer0-${ORG2}" --filter name="cli" --filter name="explorer" --filter name="explorer-db") 2>/dev/null || true

echo "Removing Docker networks..."
docker network rm "$NETWORK_NAME" 2>/dev/null || true

echo "Removing dangling Docker volumes (if any)..."
docker volume rm $(docker volume ls -qf dangling=true) 2>/dev/null || true

echo "Removing local deployment directories and files..."
if [ -d "$PROJECT_NAME" ]; then
    rm -rf "$PROJECT_NAME"
fi
# Ensure this directory is completely gone before proceeding
if [ -d "$PROJECT_NAME" ]; then
    echo "Error: Failed to remove $PROJECT_NAME directory. Please remove it manually."
    exit 1
fi

echo "Pulling Docker images..."
docker pull --platform linux/amd64 "$FABRIC_CA_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_ORDERER_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_PEER_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_TOOLS_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_COUCHDB_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_EXPLORER_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_EXPLORER_DB_IMAGE" || true

echo "Creating directory structure: $PROJECT_NAME/..."
mkdir -p "$PROJECT_NAME"/{organizations,configtx,docker,scripts,"chaincode/$CHAINCODE_NAME",channel-artifacts,system-genesis-block,explorer}
mkdir -p "$PROJECT_NAME/organizations/${ORG1}"
mkdir -p "$PROJECT_NAME/organizations/${ORG2}"
mkdir -p "$PROJECT_NAME/organizations/${ORDERER_ORG}"
mkdir -p "$PROJECT_NAME/explorer/config"
mkdir -p "$PROJECT_NAME/explorer/connection-profile"

echo "Creating chaincode directory. Place your chaincode in: $PROJECT_NAME/chaincode/$CHAINCODE_NAME/"
mkdir -p "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/"

# Use 'EOF' with quotes to prevent variable substitution in the heredoc
cat <<'EOF' > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/basic-asset.js"
'use strict';

const { Contract } = require('fabric-contract-api');

class BasicAssetContract extends Contract {

    async initLedger(ctx) {
        console.info('============= START : Init Ledger ===========');
        const assets = [
            {
                ID: 'asset1',
                color: 'blue',
                size: 5,
                owner: 'Tom',
                appraisedValue: 100,
                docType: 'asset'
            },
            {
                ID: 'asset2',
                color: 'red',
                size: 3,
                owner: 'Jerry',
                appraisedValue: 200,
                docType: 'asset'
            }
        ];

        for (const asset of assets) {
            await ctx.stub.putState(asset.ID, Buffer.from(JSON.stringify(asset)));
            console.info(`Asset ${asset.ID} initialized`);
        }
        console.info('============= END : Init Ledger ===========');
    }

    async createAsset(ctx, id, color, size, owner, appraisedValue) {
        // Check if asset already exists
        const existing = await ctx.stub.getState(id);
        if (existing && existing.length > 0) {
            throw new Error(`Asset ${id} already exists`);
        }
        
        const asset = {
            ID: id,
            color: color,
            size: parseInt(size),
            owner: owner,
            appraisedValue: parseInt(appraisedValue),
            docType: 'asset'
        };
        
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));
        console.info(`Asset ${id} created`);
        return JSON.stringify(asset);
    }

    async queryAsset(ctx, id) {
        const assetAsBytes = await ctx.stub.getState(id);
        if (!assetAsBytes || assetAsBytes.length === 0) {
            throw new Error(`Asset ${id} does not exist`);
        }
        console.log(assetAsBytes.toString());
        return assetAsBytes.toString();
    }

    async updateAsset(ctx, id, newValue) {
        const assetAsBytes = await ctx.stub.getState(id);
        if (!assetAsBytes || assetAsBytes.length === 0) {
            throw new Error(`Asset ${id} does not exist`);
        }
        
        let asset = JSON.parse(assetAsBytes.toString());
        asset.appraisedValue = parseInt(newValue);
        asset.updatedAt = new Date().toISOString();
        
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));
        console.info(`Asset ${id} updated to value ${newValue}`);
        return JSON.stringify(asset);
    }

    async getAllAssets(ctx) {
        const allResults = [];
        const iterator = await ctx.stub.getStateByRange('', '');
        let result = await iterator.next();
        while (!result.done) {
            const strValue = Buffer.from(result.value.value.toString()).toString('utf8');
            let record;
            try {
                record = JSON.parse(strValue);
            } catch (err) {
                console.log(err);
                record = strValue;
            }
            if (record.docType === 'asset') {
                allResults.push(record);
            }
            result = await iterator.next();
        }
        return JSON.stringify(allResults);
    }
}

module.exports = BasicAssetContract;
EOF

cat <<'EOF' > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/index.js"
'use strict';

const BasicAssetContract = require('./basic-asset.js');

module.exports.contracts = [BasicAssetContract];
EOF

cat <<'EOF' > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/package.json"
{
  "name": "basic-asset",
  "version": "1.0.0",
  "description": "Basic Asset Chaincode for Fabric Test Network",
  "main": "index.js",
  "engines": {
    "node": ">=16",
    "npm": ">=8"
  },
  "scripts": {
    "start": "fabric-chaincode-node start"
  },
  "author": "Your Name",
  "license": "ISC",
  "dependencies": {
    "fabric-contract-api": "~2.5.0",
    "fabric-shim": "~2.5.0"
  }
}
EOF

## --- SECTION 2: HYPERLEDGER FABRIC CONFIGURATION FILES ---
echo "=================================================="
echo "SECTION 2: HYPERLEDGER FABRIC CONFIGURATION FILES"
echo "=================================================="

echo "Creating configtx.yaml..."
cat > "$PROJECT_NAME/configtx/configtx.yaml" <<EOF
Organizations:
  - &${ORG1}
    Name: ${ORG1}
    ID: ${ORG1}MSP
    MSPDir: ../organizations/${ORG1}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('${ORG1}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('${ORG1}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('${ORG1}MSP.admin')"
    AnchorPeers:
      - Host: peer0-${ORG1}.${ORG1_DOMAIN}
        Port: 7051
  - &${ORG2}
    Name: ${ORG2}
    ID: ${ORG2}MSP
    MSPDir: ../organizations/${ORG2}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('${ORG2}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('${ORG2}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('${ORG2}MSP.admin')"
    AnchorPeers:
      - Host: peer0-${ORG2}.${ORG2_DOMAIN}
        Port: 9051
  - &${ORDERER_ORG}
    Name: ${ORDERER_ORG}
    ID: ${ORDERER_ORG}MSP
    MSPDir: ../organizations/${ORDERER_ORG}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('${ORDERER_ORG}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('${ORDERER_ORG}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('${ORDERER_ORG}MSP.admin')"

Capabilities:
  Channel: &ChannelCapabilities
    V2_0: true
  Orderer: &OrdererCapabilities
    V2_0: true
  Application: &ApplicationCapabilities
    V2_0: true

Orderer: &OrdererDefaults
  OrdererType: etcdraft
  Addresses:
    - orderer.${ORDERER_DOMAIN}:7050
  BatchTimeout: 2s
  BatchSize:
    MaxMessageCount: 10
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 512 KB
  EtcdRaft:
    Consenters:
      - Host: orderer.${ORDERER_DOMAIN}
        Port: 7050
        ClientTLSCert: /organizations/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/server.crt
        ServerTLSCert: /organizations/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/server.crt
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"
  Capabilities:
    <<: *OrdererCapabilities

Application: &ApplicationDefaults
  Organizations:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    LifecycleEndorsement:
      Type: Signature
      Rule: "OR('${ORG1}MSP.member', '${ORG2}MSP.member')"
    Endorsement:
      Type: Signature
      Rule: "OR('${ORG1}MSP.member', '${ORG2}MSP.member')"
  Capabilities:
    <<: *ApplicationCapabilities

Channel: &ChannelDefaults
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
  Capabilities:
    <<: *ChannelCapabilities

Profiles:
  TwoOrgsOrdererGenesis:
    <<: *ChannelDefaults
    Orderer:
      <<: *OrdererDefaults
      Organizations:
        - *${ORDERER_ORG}
      Capabilities:
        <<: *OrdererCapabilities
    Consortiums:
      SampleConsortium:
        Organizations:
          - *${ORG1}
          - *${ORG2}
  TwoOrgsChannel:
    Consortium: SampleConsortium
    <<: *ChannelDefaults
    Application:
      <<: *ApplicationDefaults
      Organizations:
        - *${ORG1}
        - *${ORG2}
      Capabilities:
        - *ApplicationCapabilities
EOF

echo "Creating docker-compose-orderer.yaml..."
cat > "$PROJECT_NAME/docker/docker-compose-orderer.yaml" <<EOF
networks:
  ${NETWORK_NAME}:
    external: true

services:
  orderer.${ORDERER_DOMAIN}:
    container_name: orderer.${ORDERER_DOMAIN}
    image: ${FABRIC_ORDERER_IMAGE}
    platform: linux/amd64
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=7050
      - ORDERER_GENERAL_GENESISMETHOD=file
      - ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/genesis-block/genesis.block
      - ORDERER_GENERAL_LOCALMSPID=${ORDERER_ORG}MSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_CONSENSUS_TYPE=etcdraft
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric
    command: orderer
    volumes:
      - ../system-genesis-block:/var/hyperledger/orderer/genesis-block
      - ../organizations/${ORDERER_ORG}/msp:/var/hyperledger/orderer/msp
      - ../organizations/${ORDERER_ORG}/tls:/var/hyperledger/orderer/tls
    ports:
      - 7050:7050
    networks:
      - ${NETWORK_NAME}
EOF

echo "Creating docker-compose-peers.yaml..."
cat > "$PROJECT_NAME/docker/docker-compose-peers.yaml" <<EOF
networks:
  ${NETWORK_NAME}:
    external: true

services:
  ca-${ORG1}.${ORG1_DOMAIN}:
    container_name: ca-${ORG1}.${ORG1_DOMAIN}
    image: ${FABRIC_CA_IMAGE}
    platform: linux/amd64
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${ORG1}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_PORT=7054
      - FABRIC_CA_SERVER_CSR_HOSTS=ca-${ORG1}.${ORG1_DOMAIN},localhost
      - FABRIC_CA_SERVER_DEBUG=true
    ports:
      - "7054:7054"
    command: sh -c 'fabric-ca-server start -b ${CA_ADMIN_USER}:${CA_ADMIN_PASS} -d'
    volumes:
      - ../organizations/${ORG1}/ca:/etc/hyperledger/fabric-ca-server
    networks:
      - ${NETWORK_NAME}

  couchdb0-${ORG1}:
    container_name: couchdb0-${ORG1}
    image: ${FABRIC_COUCHDB_IMAGE}
    platform: linux/amd64
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=adminpw
    ports:
      - "5984:5984"
    networks:
      - ${NETWORK_NAME}

  peer0-${ORG1}.${ORG1_DOMAIN}:
    container_name: peer0-${ORG1}.${ORG1_DOMAIN}
    image: ${FABRIC_PEER_IMAGE}
    platform: linux/amd64
    environment:
      - CORE_VM_ENDPOINT=unix:///var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${NETWORK_NAME}
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0-${ORG1}.${ORG1_DOMAIN}
      - CORE_PEER_ADDRESS=peer0-${ORG1}.${ORG1_DOMAIN}:7051
      - CORE_PEER_LISTENADDRESS=0.0.0.0:7051
      - CORE_PEER_CHAINCODEADDRESS=peer0-${ORG1}.${ORG1_DOMAIN}:7052
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0-${ORG1}.${ORG1_DOMAIN}:7051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0-${ORG1}.${ORG1_DOMAIN}:7051
      - CORE_PEER_LOCALMSPID=${ORG1}MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_OPERATIONS_LISTENADDRESS=0.0.0.0:9443
      - CORE_METRICS_PROVIDER=prometheus
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb0-${ORG1}:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=admin
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=adminpw
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ../organizations/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/msp:/etc/hyperledger/fabric/msp
      - ../organizations/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls:/etc/hyperledger/fabric/tls
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    ports:
      - 7051:7051
      - 9443:9443
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - ca-${ORG1}.${ORG1_DOMAIN}
      - couchdb0-${ORG1}

  ca-${ORG2}.${ORG2_DOMAIN}:
    container_name: ca-${ORG2}.${ORG2_DOMAIN}
    image: ${FABRIC_CA_IMAGE}
    platform: linux/amd64
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${ORG2}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_PORT=8054
      - FABRIC_CA_SERVER_CSR_HOSTS=ca-${ORG2}.${ORG2_DOMAIN},localhost
      - FABRIC_CA_SERVER_DEBUG=true
    ports:
      - "8054:8054"
    command: sh -c 'fabric-ca-server start -b ${CA_ADMIN_USER}:${CA_ADMIN_PASS} -d'
    volumes:
      - ../organizations/${ORG2}/ca:/etc/hyperledger/fabric-ca-server
    networks:
      - ${NETWORK_NAME}

  couchdb0-${ORG2}:
    container_name: couchdb0-${ORG2}
    image: ${FABRIC_COUCHDB_IMAGE}
    platform: linux/amd64
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=adminpw
    ports:
      - "6984:5984"
    networks:
      - ${NETWORK_NAME}

  peer0-${ORG2}.${ORG2_DOMAIN}:
    container_name: peer0-${ORG2}.${ORG2_DOMAIN}
    image: ${FABRIC_PEER_IMAGE}
    platform: linux/amd64
    environment:
      - CORE_VM_ENDPOINT=unix:///var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${NETWORK_NAME}
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0-${ORG2}.${ORG2_DOMAIN}
      - CORE_PEER_ADDRESS=peer0-${ORG2}.${ORG2_DOMAIN}:9051
      - CORE_PEER_LISTENADDRESS=0.0.0.0:9051
      - CORE_PEER_CHAINCODEADDRESS=peer0-${ORG2}.${ORG2_DOMAIN}:9052
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:9052
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0-${ORG2}.${ORG2_DOMAIN}:9051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0-${ORG2}.${ORG2_DOMAIN}:9051
      - CORE_PEER_LOCALMSPID=${ORG2}MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_OPERATIONS_LISTENADDRESS=0.0.0.0:9444
      - CORE_METRICS_PROVIDER=prometheus
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb0-${ORG2}:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=admin
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=adminpw
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ../organizations/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/msp:/etc/hyperledger/fabric/msp
      - ../organizations/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls:/etc/hyperledger/fabric/tls
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    ports:
      - 9051:9051
      - 9444:9444
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - ca-${ORG2}.${ORG2_DOMAIN}
      - couchdb0-${ORG2}

  cli:
    container_name: cli
    image: ${FABRIC_TOOLS_IMAGE}
    platform: linux/amd64
    tty: true
    stdin_open: true
    environment:
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///var/run/docker.sock
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=cli
      - CORE_PEER_ADDRESS=peer0-${ORG1}.${ORG1_DOMAIN}:7051
      - CORE_PEER_LOCALMSPID=${ORG1}MSP
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_ROOTCERT_FILE=/opt/hyperledger/fabric/crypto/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp
      - ORDERER_CA=/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/tls/ca.crt
    working_dir: /opt/peer
    command: /bin/bash
    volumes:
      - ../chaincode:/opt/gopath/src/chaincode
      - /var/run/docker.sock:/var/run/docker.sock
      - ../organizations:/opt/hyperledger/fabric/crypto
      - ../channel-artifacts:/opt/hyperledger/fabric/channel-artifacts
      - ../scripts:/opt/hyperledger/fabric/scripts
      - ../system-genesis-block:/opt/hyperledger/fabric/system-genesis-block
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - peer0-${ORG1}.${ORG1_DOMAIN}
      - peer0-${ORG2}.${ORG2_DOMAIN}
EOF

echo "Creating docker-compose-explorer.yaml..."
cat > "$PROJECT_NAME/docker/docker-compose-explorer.yaml" <<EOF
networks:
  ${NETWORK_NAME}:
    external: true

services:
  explorer-db:
    container_name: explorer-db
    image: ${FABRIC_EXPLORER_DB_IMAGE}
    platform: linux/amd64
    environment:
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWORD=password
    ports:
      - 5432:5432
    networks:
      - ${NETWORK_NAME}

  explorer:
    container_name: explorer
    image: ${FABRIC_EXPLORER_IMAGE}
    platform: linux/amd64
    environment:
      - DATABASE_HOST=explorer-db
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWORD=password
      - LOG_LEVEL_APP=info
      - LOG_LEVEL_DB=info
      - LOG_LEVEL_CONSOLE=debug
      - LOG_CONSOLE_STDOUT=true
      - DISCOVERY_AS_LOCALHOST=false
    volumes:
      - ../explorer/config/config.json:/opt/explorer/app/platform/fabric/config.json
      - ../explorer/connection-profile:/opt/explorer/app/platform/fabric/connection-profile
      - ../organizations:/tmp/crypto
    ports:
      - 8080:8080
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - explorer-db
EOF

cat > "$PROJECT_NAME/docker/docker-compose.yaml" <<EOF
networks:
  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
EOF

echo "Creating Hyperledger Explorer configuration..."
mkdir -p "$PROJECT_NAME/explorer/config"
mkdir -p "$PROJECT_NAME/explorer/connection-profile"

cat > "$PROJECT_NAME/explorer/config/config.json" <<EOF
{
  "network-configs": {
    "fabric-test-network": {
      "name": "Fabric Test Network",
      "profile": "/opt/explorer/app/platform/fabric/connection-profile/connection-profile.json"
    }
  },
  "license": "Apache-2.0"
}
EOF

# Update the Explorer connection profile with proper admin credentials
cat > "$PROJECT_NAME/explorer/connection-profile/connection-profile.json" <<EOF
{
  "name": "fabric-test-network",
  "version": "1.0.0",
  "client": {
    "tlsEnable": true,
    "adminCredential": {
      "id": "admin",
      "password": "adminpw"
    },
    "enableAuthentication": true,
    "organization": "${ORG1}",
    "connection": {
      "timeout": {
        "peer": {
          "endorser": "300"
        },
        "orderer": "300"
      }
    }
  },
  "channels": {
    "${CHANNEL_NAME}": {
      "peers": {
        "peer0-${ORG1}.${ORG1_DOMAIN}": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        },
        "peer0-${ORG2}.${ORG2_DOMAIN}": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        }
      }
    }
  },
  "organizations": {
    "${ORG1}": {
      "mspid": "${ORG1}MSP",
      "adminPrivateKey": {
        "path": "/tmp/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp/keystore/key.pem"
      },
      "peers": ["peer0-${ORG1}.${ORG1_DOMAIN}"],
      "signedCert": {
        "path": "/tmp/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp/signcerts/Admin@${ORG1_DOMAIN}-cert.pem"
      }
    },
    "${ORG2}": {
      "mspid": "${ORG2}MSP",
      "adminPrivateKey": {
        "path": "/tmp/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp/keystore/key.pem"
      },
      "peers": ["peer0-${ORG2}.${ORG2_DOMAIN}"],
      "signedCert": {
        "path": "/tmp/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp/signcerts/Admin@${ORG2_DOMAIN}-cert.pem"
      }
    }
  },
  "peers": {
    "peer0-${ORG1}.${ORG1_DOMAIN}": {
      "url": "grpcs://peer0-${ORG1}.${ORG1_DOMAIN}:7051",
      "tlsCACerts": {
        "path": "/tmp/crypto/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "peer0-${ORG1}.${ORG1_DOMAIN}",
        "hostnameOverride": "peer0-${ORG1}.${ORG1_DOMAIN}"
      }
    },
    "peer0-${ORG2}.${ORG2_DOMAIN}": {
      "url": "grpcs://peer0-${ORG2}.${ORG2_DOMAIN}:9051",
      "tlsCACerts": {
        "path": "/tmp/crypto/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "peer0-${ORG2}.${ORG2_DOMAIN}",
        "hostnameOverride": "peer0-${ORG2}.${ORG2_DOMAIN}"
      }
    }
  },
  "orderers": {
    "orderer.${ORDERER_DOMAIN}": {
      "url": "grpcs://orderer.${ORDERER_DOMAIN}:7050",
      "tlsCACerts": {
        "path": "/tmp/crypto/${ORDERER_ORG}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "orderer.${ORDERER_DOMAIN}",
        "hostnameOverride": "orderer.${ORDERER_DOMAIN}"
      }
    }
  }
}
EOF

echo "Directory structure created successfully!"
echo "Continue with the rest of the script..."

## --- SECTION 3: HELPER FUNCTIONS ---
echo "=================================================="
echo "SECTION 3: HELPER FUNCTIONS"
echo "=================================================="

_get_entity_path_segment() {
    local type=$1
    if [ "$type" == "peer" ]; then
        echo "peers"
    elif [ "$type" == "orderer" ]; then
        echo "orderers"
    elif [ "$type" == "user" ] || [ "$type" == "admin" ]; then 
        echo "users"
    else
        echo "Error: Unknown entity type '$type' for path segment generation." >&2
        exit 1
    fi
}

# Function to register and enroll identities using Fabric CA Client
register_enroll() {
  local ORG_NAME=$1
  local ORG_DOMAIN=$2
  local IDENTITY_TYPE=$3
  local IDENTITY_NAME_SHORT=$4
  local IDENTITY_PASS=${5:-"password"}
  local CA_PORT=$6
  local CA_CONTAINER_TO_USE=$7
  local CONTAINER_CA_TLS_CERT_PATH=$8
  local IDENTITY_ATTRS_STR=${9:-""}
  local CA_NAME_TO_USE=${10:-"ca-${ORG_NAME}"}

  local IDENTITY_FULL_NAME
  local DIR_SEGMENT

  if [ "$IDENTITY_TYPE" == "peer" ] || [ "$IDENTITY_TYPE" == "orderer" ]; then
    IDENTITY_FULL_NAME="${IDENTITY_NAME_SHORT}.${ORG_DOMAIN}"
    DIR_SEGMENT="${IDENTITY_TYPE}s"
  else
    IDENTITY_FULL_NAME="${IDENTITY_NAME_SHORT}@${ORG_DOMAIN}"
    DIR_SEGMENT="users"
  fi

  echo "Registering ${IDENTITY_TYPE} ${IDENTITY_FULL_NAME} for ${ORG_NAME} with CA '${CA_NAME_TO_USE}'..."

  local CA_ADMIN_HOME_IN_CA="/etc/hyperledger/fabric/organizations/${ORG_NAME}/users/${CA_ADMIN_USER}@${ORG_DOMAIN}"
  if [ "$ORG_NAME" == "$ORDERER_ORG" ]; then
    CA_ADMIN_HOME_IN_CA="/etc/hyperledger/fabric/organizations/${ORG1}/users/${CA_ADMIN_USER}@${ORG1_DOMAIN}"
  fi

  docker exec \
    -e FABRIC_CA_CLIENT_HOME="$CA_ADMIN_HOME_IN_CA" \
    "${CA_CONTAINER_TO_USE}" fabric-ca-client register \
    --caname "${CA_NAME_TO_USE}" \
    --id.name "${IDENTITY_FULL_NAME}" \
    --id.secret "${IDENTITY_PASS}" \
    --id.type "${IDENTITY_TYPE}" \
    --id.attrs "${IDENTITY_ATTRS_STR}" \
    --tls.certfiles "$CONTAINER_CA_TLS_CERT_PATH" || echo "Registration may have already occurred, continuing..."

  echo "Enrolling ${IDENTITY_TYPE} ${IDENTITY_FULL_NAME} inside CA container..."
  local IDENTITY_MSP_DIR_IN_CA_TEMP="/tmp/${IDENTITY_FULL_NAME}-msp"

  local CSR_HOSTS_FLAG=""
  if [ "$IDENTITY_TYPE" == "peer" ] || [ "$IDENTITY_TYPE" == "orderer" ]; then
    CSR_HOSTS_FLAG="--csr.hosts ${IDENTITY_FULL_NAME}"
  fi

  docker exec \
    -e FABRIC_CA_CLIENT_HOME="$IDENTITY_MSP_DIR_IN_CA_TEMP" \
    "${CA_CONTAINER_TO_USE}" fabric-ca-client enroll -u "https://${IDENTITY_FULL_NAME}:${IDENTITY_PASS}@${CA_CONTAINER_TO_USE}:${CA_PORT}" \
    --caname "${CA_NAME_TO_USE}" \
    --tls.certfiles "$CONTAINER_CA_TLS_CERT_PATH" \
    -M "$IDENTITY_MSP_DIR_IN_CA_TEMP/msp" \
    $CSR_HOSTS_FLAG

  local HOST_IDENTITY_PATH="$PROJECT_NAME/organizations/${ORG_NAME}/${DIR_SEGMENT}/${IDENTITY_FULL_NAME}"
  local HOST_IDENTITY_MSP_PATH="${HOST_IDENTITY_PATH}/msp"

  echo "Copying ${IDENTITY_TYPE} ${IDENTITY_FULL_NAME}'s MSP from CA container to host..."
  mkdir -p "$HOST_IDENTITY_MSP_PATH"
  docker cp "${CA_CONTAINER_TO_USE}:${IDENTITY_MSP_DIR_IN_CA_TEMP}/msp/." "$HOST_IDENTITY_MSP_PATH"

  if [ "$IDENTITY_TYPE" == "peer" ] || [ "$IDENTITY_TYPE" == "orderer" ]; then
      echo "Copying TLS cert for ${IDENTITY_TYPE} ${IDENTITY_FULL_NAME} to local TLS folder..."
      local NODE_TLS_PATH="${HOST_IDENTITY_PATH}/tls"
      mkdir -p "$NODE_TLS_PATH"
      cp "${HOST_IDENTITY_MSP_PATH}/keystore"/* "${NODE_TLS_PATH}/server.key"
      cp "${HOST_IDENTITY_MSP_PATH}/signcerts"/* "${NODE_TLS_PATH}/server.crt"
      cp "$PROJECT_NAME/organizations/${ORG_NAME}/msp/tlscacerts/tlsca.${ORG_DOMAIN}-cert.pem" "${NODE_TLS_PATH}/ca.crt"
  fi

  docker exec "${CA_CONTAINER_TO_USE}" rm -rf "$IDENTITY_MSP_DIR_IN_CA_TEMP"
}

function enroll_ca_admin {
  local ORG_NAME=$1
  local ORG_DOMAIN=$2
  local CA_ADMIN_USER=$3
  local CA_ADMIN_PASS=$4
  local CA_PORT=$5
  local CA_CONTAINER_TO_USE=$6
  local CONTAINER_CA_TLS_CERT_PATH=$7 

  echo "Enrolling CA admin for ${ORG_NAME} from CA container ${CA_CONTAINER_TO_USE}..."
  local ADMIN_MSP_HOME_IN_CA="/etc/hyperledger/fabric/organizations/${ORG_NAME}/users/${CA_ADMIN_USER}@${ORG_DOMAIN}"

  docker exec \
    -e FABRIC_CA_CLIENT_HOME="$ADMIN_MSP_HOME_IN_CA" \
    "${CA_CONTAINER_TO_USE}" fabric-ca-client enroll \
    -u "https://${CA_ADMIN_USER}:${CA_ADMIN_PASS}@${CA_CONTAINER_TO_USE}:${CA_PORT}" \
    --caname "ca-${ORG_NAME}" \
    --tls.certfiles "$CONTAINER_CA_TLS_CERT_PATH" \
    -M "$ADMIN_MSP_HOME_IN_CA/msp"

  echo "Renaming admin's private key inside CA container for ${ORG_NAME}..."
  docker exec "${CA_CONTAINER_TO_USE}" /bin/bash -c \
    "mv \"$ADMIN_MSP_HOME_IN_CA/msp/keystore\"/* \"$ADMIN_MSP_HOME_IN_CA/msp/keystore/key.pem\" 2>/dev/null || true"

  echo "Copying CA admin's MSP from CA container to host for ${ORG_NAME}..."
  local HOST_ADMIN_MSP_PATH="$PROJECT_NAME/organizations/${ORG_NAME}/users/${CA_ADMIN_USER}@${ORG_DOMAIN}/msp"
  mkdir -p "$HOST_ADMIN_MSP_PATH"
  docker cp "${CA_CONTAINER_TO_USE}:${ADMIN_MSP_HOME_IN_CA}/msp/." "$HOST_ADMIN_MSP_PATH" 2>/dev/null || true
}

create_msp_structure() {
    local org=$1
    local domain=$2
    local ca_port_for_getcacert=$3
    local ca_container_name_for_getcacert=$4
    local abs_project_path="$(pwd)/$PROJECT_NAME" 

    local host_org_base_dir="$abs_project_path/organizations/$org"
    local host_org_msp_dir="$host_org_base_dir/msp"
    local host_org_ca_config_dir="$host_org_base_dir/ca" 

    mkdir -p "$host_org_msp_dir"/{admincerts,cacerts,tlscacerts,users,keystore,signcerts}
    mkdir -p "$host_org_ca_config_dir"

    local container_path_to_ca_own_tls_cert="/etc/hyperledger/fabric-ca-server/ca-cert.pem"
    local host_storage_for_ca_tls_cert="$host_org_ca_config_dir/fetched-ca-tls-cert.pem"

    echo "Fetching CA's own TLS cert for $org from $ca_container_name_for_getcacert and saving to $host_storage_for_ca_tls_cert..." >&2
    local attempts=0
    local max_attempts=5
    local success=false
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        set +e 
        docker exec "$ca_container_name_for_getcacert" cat "$container_path_to_ca_own_tls_cert" > "$host_storage_for_ca_tls_cert"
        if [ $? -eq 0 ] && [ -s "$host_storage_for_ca_tls_cert" ]; then
            success=true
        else
            attempts=$((attempts+1))
            echo "Attempt $attempts/$max_attempts: Failed to fetch CA TLS cert for $org, or cert is empty. Retrying in 3s..." >&2
            sleep 3
        fi
        set -e
    done
    if [ "$success" = false ]; then
        echo "Error: Could not fetch CA TLS cert for $org from $ca_container_name_for_getcacert after $max_attempts attempts. Check CA logs." >&2
        exit 1
    fi

    echo "Fetching CA root signing cert for $org's MSP using docker exec..." >&2
    
    docker exec \
        -e FABRIC_CA_CLIENT_HOME="/etc/hyperledger/fabric-ca-client" \
        "$ca_container_name_for_getcacert" \
        fabric-ca-client getcacert \
        -u "https://${ca_container_name_for_getcacert}:${ca_port_for_getcacert}" \
        --tls.certfiles "$container_path_to_ca_own_tls_cert" \
        -M "/tmp/${org}-msp"

    echo "Copying MSP files from container to host..." >&2
    mkdir -p "$host_org_msp_dir/cacerts"
    mkdir -p "$host_org_msp_dir/tlscacerts"
    
    docker cp "${ca_container_name_for_getcacert}:/tmp/${org}-msp/cacerts/." "$host_org_msp_dir/cacerts/" 2>/dev/null || true
    
    local retrieved_ca_signing_cert_file=$(ls "$host_org_msp_dir/cacerts/" 2>/dev/null | head -1)
    
    if [ -z "$retrieved_ca_signing_cert_file" ]; then
        echo "Error: Failed to retrieve CA root signing cert for $org. No certificate found." >&2
        exit 1
    fi

    cp "$host_org_msp_dir/cacerts/$retrieved_ca_signing_cert_file" \
       "$host_org_msp_dir/tlscacerts/tlsca.$domain-cert.pem"

    docker exec "$ca_container_name_for_getcacert" rm -rf "/tmp/${org}-msp"

    echo "Creating config.yaml for $org's MSP..." >&2
    cat > "$host_org_msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_file}
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_file}
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_file}
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_file}
    OrganizationalUnitIdentifier: orderer
EOF
    
    echo "$container_path_to_ca_own_tls_cert"
}

register_affiliation() {
    local ca_container_to_target=$1
    local ca_port_to_target=$2
    local path_to_ca_tls_cert_in_container=$3
    local affiliation_to_register=$4
    local admin_user_for_cmd=$5
    local admin_pass_for_cmd=$6
    local org_name_for_admin_path=$7 

    echo "Registering affiliation '$affiliation_to_register' with CA '$ca_container_to_target'..." >&2

    local container_client_home_for_exec="/etc/hyperledger/fabric/organizations/${org_name_for_admin_path}/users/${admin_user_for_cmd}@${org_name_for_admin_path/Org/.example.com}/"

    set +e 
    docker exec -e FABRIC_CA_CLIENT_HOME="${container_client_home_for_exec}" "$ca_container_to_target" \
        fabric-ca-client affiliation add "$affiliation_to_register" \
        --tls.certfiles "$path_to_ca_tls_cert_in_container" 2>/dev/null
    local exit_code=$?
    set -e 

    if [ $exit_code -ne 0 ]; then
        echo "Warning: Adding affiliation '$affiliation_to_register' resulted in exit code $exit_code. It might already exist or another error occurred. Continuing." >&2
    else
        echo "Affiliation '$affiliation_to_register' added successfully or already existed." >&2
    fi
}

check_chaincode_installed() {
    local PEER_ADDRESS=$1
    local TLS_ROOT_CERT_FILE=$2
    local ORG_MSP_ID=$3       
    local ADMIN_MSP_PATH=$4   

    echo "Checking if chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is installed on ${PEER_ADDRESS}..."

    local installed_output
    if [ -n "$ORG_MSP_ID" ] && [ -n "$ADMIN_MSP_PATH" ]; then
        installed_output=$(docker exec \
            -e CORE_PEER_LOCALMSPID="$ORG_MSP_ID" \
            -e CORE_PEER_ADDRESS="$PEER_ADDRESS" \
            -e CORE_PEER_MSPCONFIGPATH="$ADMIN_MSP_PATH" \
            -e CORE_PEER_TLS_ROOTCERT_FILE="$TLS_ROOT_CERT_FILE" \
            cli peer lifecycle chaincode queryinstalled --peerAddresses "$PEER_ADDRESS" --tlsRootCertFiles "$TLS_ROOT_CERT_FILE" 2>&1)
    else
        installed_output=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "$PEER_ADDRESS" --tlsRootCertFiles "$TLS_ROOT_CERT_FILE" 2>&1)
    fi

    echo "$installed_output" | grep -q "Label: ${CHAINCODE_NAME}_${CHAINCODE_VERSION}"
    if [ $? -eq 0 ]; then
        echo "Chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is already installed on ${PEER_ADDRESS}. Skipping installation."
        return 0 
    else
        echo "Chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is NOT installed on ${PEER_ADDRESS}."
        return 1 
    fi
}

## --- SECTION 4: NETWORK SETUP AND IDENTITY GENERATION ---
echo "=================================================="
echo "SECTION 4: NETWORK SETUP AND IDENTITY GENERATION"
echo "=================================================="

echo "Creating Docker network: $NETWORK_NAME"
docker network create "$NETWORK_NAME" 2>/dev/null || true

echo "Cleaning up any existing CA containers and volumes..."
docker stop ca-${ORG1}.${ORG1_DOMAIN} ca-${ORG2}.${ORG2_DOMAIN} 2>/dev/null || true
docker rm ca-${ORG1}.${ORG1_DOMAIN} ca-${ORG2}.${ORG2_DOMAIN} 2>/dev/null || true

docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" down --remove-orphans 2>/dev/null || true
docker compose -f "$PROJECT_NAME/docker/docker-compose-orderer.yaml" down --remove-orphans 2>/dev/null || true

echo "Creating CA directories with proper permissions..."
mkdir -p "$PROJECT_NAME/organizations/${ORG1}/ca"
mkdir -p "$PROJECT_NAME/organizations/${ORG2}/ca"
mkdir -p "$PROJECT_NAME/organizations/${ORG1}/peers"
mkdir -p "$PROJECT_NAME/organizations/${ORG2}/peers"
mkdir -p "$PROJECT_NAME/organizations/${ORDERER_ORG}/orderers"

chmod 755 "$PROJECT_NAME/organizations/${ORG1}/ca" 2>/dev/null || true
chmod 755 "$PROJECT_NAME/organizations/${ORG2}/ca" 2>/dev/null || true

echo "Starting CAs..."
docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" up -d "ca-${ORG1}.${ORG1_DOMAIN}" "ca-${ORG2}.${ORG2_DOMAIN}"
echo "Waiting for CAs to start (15s)..."
sleep 15

echo "Creating organization MSP structures and enrolling CA admin users..."

ORG1_CA_INTERNAL_TLS_CERT_PATH=$(create_msp_structure "$ORG1" "$ORG1_DOMAIN" 7054 "ca-${ORG1}.${ORG1_DOMAIN}")
enroll_ca_admin "$ORG1" "$ORG1_DOMAIN" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" 7054 "ca-${ORG1}.${ORG1_DOMAIN}" "$ORG1_CA_INTERNAL_TLS_CERT_PATH"
cp "$PROJECT_NAME/organizations/$ORG1/users/$CA_ADMIN_USER@$ORG1_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORG1/msp/admincerts/" 2>/dev/null || true
cp "$PROJECT_NAME/organizations/$ORG1/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG1/users/$CA_ADMIN_USER@$ORG1_DOMAIN/msp/" 2>/dev/null || true
cp -R "$PROJECT_NAME/organizations/$ORG1/msp/cacerts/." "$PROJECT_NAME/organizations/$ORG1/users/$CA_ADMIN_USER@$ORG1_DOMAIN/msp/cacerts/" 2>/dev/null || true

ORG2_CA_INTERNAL_TLS_CERT_PATH=$(create_msp_structure "$ORG2" "$ORG2_DOMAIN" 8054 "ca-${ORG2}.${ORG2_DOMAIN}")
enroll_ca_admin "$ORG2" "$ORG2_DOMAIN" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" 8054 "ca-${ORG2}.${ORG2_DOMAIN}" "$ORG2_CA_INTERNAL_TLS_CERT_PATH"
cp "$PROJECT_NAME/organizations/$ORG2/users/$CA_ADMIN_USER@$ORG2_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORG2/msp/admincerts/" 2>/dev/null || true
cp "$PROJECT_NAME/organizations/$ORG2/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG2/users/$CA_ADMIN_USER@$ORG2_DOMAIN/msp/" 2>/dev/null || true
cp -R "$PROJECT_NAME/organizations/$ORG2/msp/cacerts/." "$PROJECT_NAME/organizations/$ORG2/users/$CA_ADMIN_USER@$ORG2_DOMAIN/msp/cacerts/" 2>/dev/null || true

ORDERER_ISSUING_CA_NAME="ca-${ORG1}.${ORG1_DOMAIN}"
ORDERER_ISSUING_CA_PORT=7054
ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH="$ORG1_CA_INTERNAL_TLS_CERT_PATH"
create_msp_structure "$ORDERER_ORG" "$ORDERER_DOMAIN" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_NAME"

echo "Registering affiliations..."
register_affiliation "ca-${ORG1}.${ORG1_DOMAIN}" 7054 "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "$ORG1" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true
register_affiliation "ca-${ORG1}.${ORG1_DOMAIN}" 7054 "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "$ORG1.peer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true
register_affiliation "ca-${ORG1}.${ORG1_DOMAIN}" 7054 "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "$ORG1.user" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true
register_affiliation "ca-${ORG1}.${ORG1_DOMAIN}" 7054 "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "$ORG1.admin" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true

register_affiliation "ca-${ORG2}.${ORG2_DOMAIN}" 8054 "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "$ORG2" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG2" 2>/dev/null || true
register_affiliation "ca-${ORG2}.${ORG2_DOMAIN}" 8054 "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "$ORG2.peer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG2" 2>/dev/null || true
register_affiliation "ca-${ORG2}.${ORG2_DOMAIN}" 8054 "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "$ORG2.user" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG2" 2>/dev/null || true
register_affiliation "ca-${ORG2}.${ORG2_DOMAIN}" 8054 "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "$ORG2.admin" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG2" 2>/dev/null || true

register_affiliation "$ORDERER_ISSUING_CA_NAME" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" "$ORDERER_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true
register_affiliation "$ORDERER_ISSUING_CA_NAME" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" "$ORDERER_ORG.orderer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$ORG1" 2>/dev/null || true

echo "Registering and enrolling identities for nodes and users..."

register_enroll "$ORG1" "$ORG1_DOMAIN" peer "peer0-${ORG1}" "${CA_ADMIN_PASS}" 7054 "ca-${ORG1}.${ORG1_DOMAIN}" "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=peer" || true
echo "Populating peer0-${ORG1}.${ORG1_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$ORG1/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG1/peers/peer0-${ORG1}.${ORG1_DOMAIN}/msp/" 2>/dev/null || true
mkdir -p "$PROJECT_NAME/organizations/$ORG1/peers/peer0-${ORG1}.${ORG1_DOMAIN}/msp/admincerts"
cp "$PROJECT_NAME/organizations/$ORG1/users/Admin@$ORG1_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORG1/peers/peer0-${ORG1}.${ORG1_DOMAIN}/msp/admincerts/" 2>/dev/null || true

register_enroll "$ORG1" "$ORG1_DOMAIN" user "User1" "${CA_ADMIN_PASS}" 7054 "ca-${ORG1}.${ORG1_DOMAIN}" "$ORG1_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=client" || true
cp "$PROJECT_NAME/organizations/$ORG1/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG1/users/User1@$ORG1_DOMAIN/msp/" 2>/dev/null || true
mkdir -p "$PROJECT_NAME/organizations/$ORG1/users/User1@$ORG1_DOMAIN/msp/cacerts"
cp -R "$PROJECT_NAME/organizations/$ORG1/msp/cacerts/." "$PROJECT_NAME/organizations/$ORG1/users/User1@$ORG1_DOMAIN/msp/cacerts/" 2>/dev/null || true

register_enroll "$ORG2" "$ORG2_DOMAIN" peer "peer0-${ORG2}" "${CA_ADMIN_PASS}" 8054 "ca-${ORG2}.${ORG2_DOMAIN}" "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=peer" || true
echo "Populating peer0-${ORG2}.${ORG2_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$ORG2/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG2/peers/peer0-${ORG2}.${ORG2_DOMAIN}/msp/" 2>/dev/null || true
mkdir -p "$PROJECT_NAME/organizations/$ORG2/peers/peer0-${ORG2}.${ORG2_DOMAIN}/msp/admincerts"
cp "$PROJECT_NAME/organizations/$ORG2/users/Admin@$ORG2_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORG2/peers/peer0-${ORG2}.${ORG2_DOMAIN}/msp/admincerts/" 2>/dev/null || true

register_enroll "$ORG2" "$ORG2_DOMAIN" user "User1" "${CA_ADMIN_PASS}" 8054 "ca-${ORG2}.${ORG2_DOMAIN}" "$ORG2_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=client" || true
cp "$PROJECT_NAME/organizations/$ORG2/msp/config.yaml" "$PROJECT_NAME/organizations/$ORG2/users/User1@$ORG2_DOMAIN/msp/" 2>/dev/null || true
mkdir -p "$PROJECT_NAME/organizations/$ORG2/users/User1@$ORG2_DOMAIN/msp/cacerts"
cp -R "$PROJECT_NAME/organizations/$ORG2/msp/cacerts/." "$PROJECT_NAME/organizations/$ORG2/users/User1@$ORG2_DOMAIN/msp/cacerts/" 2>/dev/null || true

register_enroll "$ORDERER_ORG" "$ORDERER_DOMAIN" orderer "orderer" \
  "${CA_ADMIN_PASS}" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_NAME" \
  "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" \
  "affiliation=${ORDERER_ORG}.orderer" \
  "ca-${ORG1}" || true

echo "Populating orderer.${ORDERER_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/" 2>/dev/null || true
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/admincerts"
cp "$PROJECT_NAME/organizations/$ORG1/users/$CA_ADMIN_USER@$ORG1_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/admincerts/" 2>/dev/null || true

ORDERER_NODE_CRYPTO_BASE_PATH="$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/signcerts"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/admincerts"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/tls"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/keystore"

cp "$ORDERER_NODE_CRYPTO_BASE_PATH/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/signcerts/" 2>/dev/null || true
cp "$PROJECT_NAME/organizations/$ORG1/users/Admin@$ORG1_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/admincerts/" 2>/dev/null || true
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/ca.crt" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/ca.crt" 2>/dev/null || true
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/server.crt" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/server.crt" 2>/dev/null || true
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/server.key" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/server.key" 2>/dev/null || true
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/msp/keystore"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/keystore/" 2>/dev/null || true

echo "Generating genesis block (system channel) with Raft consensus..."
docker run --rm \
  -v "$PWD/$PROJECT_NAME/configtx:/configtx" \
  -v "$PWD/$PROJECT_NAME/system-genesis-block:/system-genesis-block" \
  -v "$PWD/$PROJECT_NAME/organizations:/organizations" \
  -e FABRIC_CFG_PATH=/configtx \
  -w /configtx \
  ${FABRIC_TOOLS_IMAGE} \
  configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock /system-genesis-block/genesis.block

echo "Generating channel configuration transaction for '${CHANNEL_NAME}'..."
docker run --rm \
  -v "$PWD/$PROJECT_NAME/configtx:/configtx" \
  -v "$PWD/$PROJECT_NAME/channel-artifacts:/channel-artifacts" \
  -v "$PWD/$PROJECT_NAME/organizations:/organizations" \
  -e FABRIC_CFG_PATH=/configtx \
  -w /configtx \
  ${FABRIC_TOOLS_IMAGE} \
  configtxgen -profile TwoOrgsChannel -outputCreateChannelTx /channel-artifacts/$CHANNEL_NAME.tx -channelID "$CHANNEL_NAME"

echo "Generating anchor peer update transactions..."
docker run --rm \
  -v "$PWD/$PROJECT_NAME/configtx:/configtx" \
  -v "$PWD/$PROJECT_NAME/channel-artifacts:/channel-artifacts" \
  -v "$PWD/$PROJECT_NAME/organizations:/organizations" \
  -e FABRIC_CFG_PATH=/configtx \
  -w /configtx \
  ${FABRIC_TOOLS_IMAGE} \
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /channel-artifacts/${ORG1}Anchor.tx -channelID "$CHANNEL_NAME" -asOrg "$ORG1"

docker run --rm \
  -v "$PWD/$PROJECT_NAME/configtx:/configtx" \
  -v "$PWD/$PROJECT_NAME/channel-artifacts:/channel-artifacts" \
  -v "$PWD/$PROJECT_NAME/organizations:/organizations" \
  -e FABRIC_CFG_PATH=/configtx \
  -w /configtx \
  ${FABRIC_TOOLS_IMAGE} \
  configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate /channel-artifacts/${ORG2}Anchor.tx -channelID "$CHANNEL_NAME" -asOrg "$ORG2"

echo "Starting orderer, peers, couchdb, and CLI containers..."
docker compose -f "$PROJECT_NAME/docker/docker-compose-orderer.yaml" up -d
docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" up -d

echo "Waiting for network components to initialize (30s)..."
sleep 30

## --- SECTION 5: CHANNEL OPERATIONS ---
echo "=================================================="
echo "SECTION 5: CHANNEL OPERATIONS"
echo "=================================================="

ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/tls/ca.crt"

echo "Creating channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer channel create \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "$CHANNEL_NAME" \
  -f "/opt/hyperledger/fabric/channel-artifacts/$CHANNEL_NAME.tx" \
  --outputBlock "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"

echo "Joining Org1 peer (peer0-${ORG1}.${ORG1_DOMAIN}) to channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  -e CORE_PEER_ADDRESS="peer0-${ORG1}.${ORG1_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt" \
  cli peer channel join -b "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block"

echo "Joining Org2 peer (peer0-${ORG2}.${ORG2_DOMAIN}) to channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${ORG2}.${ORG2_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls/ca.crt" \
  cli peer channel join -b "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block"

echo "Updating anchor peers for Org1 on channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  -e CORE_PEER_ADDRESS="peer0-${ORG1}.${ORG1_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt" \
  cli peer channel update \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "${CHANNEL_NAME}" \
  -f "/opt/hyperledger/fabric/channel-artifacts/${ORG1}Anchor.tx" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"

echo "Updating anchor peers for Org2 on channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${ORG2}.${ORG2_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls/ca.crt" \
  cli peer channel update \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "${CHANNEL_NAME}" \
  -f "/opt/hyperledger/fabric/channel-artifacts/${ORG2}Anchor.tx" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"
  
ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/ca.crt"
ORG1_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt"
ORG2_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls/ca.crt"

## --- SECTION 6: CHANNEL CONFIG UPDATE DEMONSTRATION ---
echo "=================================================="
echo "SECTION 6: CHANNEL CONFIG UPDATE DEMONSTRATION"
echo "=================================================="

ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/ca.crt"

echo "Ensuring orderer org MSP has admin certificate..."
docker exec cli mkdir -p /opt/hyperledger/fabric/crypto/${ORDERER_ORG}/msp/admincerts
docker exec cli cp /opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp/signcerts/* /opt/hyperledger/fabric/crypto/${ORDERER_ORG}/msp/admincerts/ 2>/dev/null || true

docker exec cli mkdir -p /tmp/config_update

echo "Fetching current channel configuration..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer channel fetch config /tmp/config_update/config_block.pb \
  -o orderer.${ORDERER_DOMAIN}:7050 \
  -c ${CHANNEL_NAME} \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI"

echo "Decoding config block..."
docker exec cli configtxlator proto_decode \
  --input /tmp/config_update/config_block.pb \
  --type common.Block \
  --output /tmp/config_update/config_block.json

echo "Extracting config..."
docker exec cli sh -c "jq .data.data[0].payload.data.config /tmp/config_update/config_block.json > /tmp/config_update/config.json"

echo "Creating a dummy channel config update (modifying batch timeout)..."
docker exec cli sh -c "jq '.channel_group.groups.Orderer.values.BatchTimeout.value.timeout = \"3s\"' /tmp/config_update/config.json > /tmp/config_update/modified_config.json"

echo "Encoding original config..."
docker exec cli configtxlator proto_encode \
  --input /tmp/config_update/config.json \
  --type common.Config \
  --output /tmp/config_update/config.pb

echo "Encoding modified config..."
docker exec cli configtxlator proto_encode \
  --input /tmp/config_update/modified_config.json \
  --type common.Config \
  --output /tmp/config_update/modified_config.pb

echo "Computing config update..."
docker exec cli configtxlator compute_update \
  --channel_id ${CHANNEL_NAME} \
  --original /tmp/config_update/config.pb \
  --updated /tmp/config_update/modified_config.pb \
  --output /tmp/config_update/config_update.pb

echo "Decoding config update..."
docker exec cli configtxlator proto_decode \
  --input /tmp/config_update/config_update.pb \
  --type common.ConfigUpdate \
  --output /tmp/config_update/config_update.json

echo "Creating config update envelope..."
docker exec cli sh -c "echo '{\"payload\":{\"header\":{\"channel_header\":{\"channel_id\":\"${CHANNEL_NAME}\",\"type\":2}},\"data\":{\"config_update\":' > /tmp/config_update/config_update_in_envelope.json"
docker exec cli sh -c "cat /tmp/config_update/config_update.json >> /tmp/config_update/config_update_in_envelope.json"
docker exec cli sh -c "echo '}}}' >> /tmp/config_update/config_update_in_envelope.json"

echo "Encoding config update envelope..."
docker exec cli configtxlator proto_encode \
  --input /tmp/config_update/config_update_in_envelope.json \
  --type common.Envelope \
  --output /tmp/config_update/config_update_in_envelope.pb

if [ $? -eq 0 ]; then
    echo "Config update envelope created successfully"
else
    echo "Error creating config update envelope"
    exit 1
fi

echo "Signing config update by Org1 admin (as OrdererOrg admin)..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORDERER_ORG}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer channel signconfigtx -f /tmp/config_update/config_update_in_envelope.pb

echo "Signing config update by Org2 admin..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  cli peer channel signconfigtx -f /tmp/config_update/config_update_in_envelope.pb

echo "Submitting channel config update with OrdererOrg MSP ID..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORDERER_ORG}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer channel update \
  -f /tmp/config_update/config_update_in_envelope.pb \
  -c ${CHANNEL_NAME} \
  -o orderer.${ORDERER_DOMAIN}:7050 \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI"

if [ $? -eq 0 ]; then
    echo "Channel config update completed successfully!"
else
    echo "Error submitting channel config update"
fi

docker exec cli rm -rf /tmp/config_update

## --- SECTION 7: CHAINCODE DEPLOYMENT ---
echo "=================================================="
echo "SECTION 7: CHAINCODE DEPLOYMENT"
echo "=================================================="

echo "Packaging chaincode '${CHAINCODE_NAME}'..."
docker exec cli peer lifecycle chaincode package "${CHAINCODE_NAME}.tar.gz" \
  --path "/opt/gopath/src/chaincode/${CHAINCODE_NAME}" \
  --lang "$CHAINCODE_LANG" \
  --label "${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

echo "Installing chaincode on Org1 peer..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${ORG1}.${ORG1_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

echo "Installing chaincode on Org2 peer..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${ORG2}.${ORG2_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

echo "Querying installed chaincode on Org1 peer to get package ID..."
CC_PACKAGE_ID=""
MAX_ATTEMPTS=5
for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
    echo "Attempt ${i}/${MAX_ATTEMPTS}..."
    set +e
    CC_PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" 2>/dev/null | grep "Package ID:" | sed -n 's/Package ID: \(.*\), Label:.*/\1/p')
    set -e
    if [ -n "$CC_PACKAGE_ID" ]; then
        echo "Successfully retrieved Package ID: ${CC_PACKAGE_ID}"
        break
    fi
    echo "Failed to retrieve Package ID. Retrying in 3 seconds..."
    sleep 3
done

if [ -z "$CC_PACKAGE_ID" ]; then
    echo "Error: Could not retrieve chaincode package ID from Org1 peer."
    exit 1
fi

echo "Approving chaincode definition for Org1..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${ORG1}.${ORG1_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${ORG1}MSP.peer','${ORG2}MSP.peer')"

echo "Approving chaincode definition for Org2..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${ORG2}.${ORG2_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${ORG1}MSP.peer','${ORG2}MSP.peer')"

echo "Checking commit readiness..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${ORG1}.${ORG1_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode checkcommitreadiness \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${ORG1}MSP.peer','${ORG2}MSP.peer')" --output json

echo "Committing chaincode definition..."
docker exec \
  cli peer lifecycle chaincode commit \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${ORG1}MSP.peer','${ORG2}MSP.peer')" \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${ORG2}.${ORG2_DOMAIN}:9051" --tlsRootCertFiles "$ORG2_PEER_TLS_CA_PATH_IN_CLI"

echo "Querying committed chaincode definition..."
docker exec \
  cli peer lifecycle chaincode querycommitted \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI"

echo "Initializing chaincode (calling 'InitLedger')..."
docker exec cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" --isInit \
  -c '{"Args":["initLedger"]}' \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${ORG2}.${ORG2_DOMAIN}:9051" --tlsRootCertFiles "$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

echo "Waiting for chaincode initialization to complete (5s)..."
sleep 5

## --- SECTION 8: DEMONSTRATE TRANSACTIONS ---
echo "=================================================="
echo "SECTION 8: DEMONSTRATING TRANSACTIONS FROM BOTH ORGS"
echo "=================================================="

echo "Transaction 1: Creating asset 'asset100' from Org1 identity..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["createAsset","asset100","blue","5","Org1User","100"]}' \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${ORG2}.${ORG2_DOMAIN}:9051" --tlsRootCertFiles "$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

sleep 2

echo "Transaction 2: Creating asset 'asset200' from Org2 identity..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["createAsset","asset200","red","3","Org2User","200"]}' \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${ORG2}.${ORG2_DOMAIN}:9051" --tlsRootCertFiles "$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

sleep 2

echo "Transaction 3: Updating asset 'asset100' from Org1 identity..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["updateAsset","asset100","150"]}' \
  --peerAddresses "peer0-${ORG1}.${ORG1_DOMAIN}:7051" --tlsRootCertFiles "$ORG1_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${ORG2}.${ORG2_DOMAIN}:9051" --tlsRootCertFiles "$ORG2_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

sleep 2

echo "Transaction 4: Querying asset 'asset100' from Org2 identity..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG2}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp" \
  cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["queryAsset","asset100"]}'

sleep 1

echo "Transaction 5: Getting all assets from Org1 identity..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${ORG1}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp" \
  cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["getAllAssets"]}'

## --- SECTION 9: STARTING HYPERLEDGER EXPLORER ---
echo "=================================================="
echo "SECTION 9: STARTING HYPERLEDGER EXPLORER"
echo "=================================================="

# Stop and remove existing Explorer containers
echo "Cleaning up existing Explorer containers..."
docker stop explorer explorer-db 2>/dev/null || true
docker rm explorer explorer-db 2>/dev/null || true

# Create necessary directories
mkdir -p "$PROJECT_NAME/explorer/config"
mkdir -p "$PROJECT_NAME/explorer/connection-profile"
mkdir -p "$PROJECT_NAME/explorer/crypto"

# Copy crypto material to Explorer directory
echo "Copying crypto material for Explorer..."
cp -r "$PROJECT_NAME/organizations" "$PROJECT_NAME/explorer/crypto/" 2>/dev/null || true

# Fix private key naming - this is critical!
find "$PROJECT_NAME/explorer/crypto/organizations" -name "*_sk" -exec sh -c 'cp "$1" "${1%_sk}.pem"' _ {} \; 2>/dev/null || true

# Create Explorer config.json
cat > "$PROJECT_NAME/explorer/config/config.json" <<EOF
{
  "network-configs": {
    "fabric-test-network": {
      "name": "Fabric Test Network",
      "profile": "/opt/explorer/app/platform/fabric/connection-profile/connection-profile.json"
    }
  },
  "license": "Apache-2.0"
}
EOF

# Create connection profile with admin credentials
cat > "$PROJECT_NAME/explorer/connection-profile/connection-profile.json" <<EOF
{
  "name": "fabric-test-network",
  "version": "1.0.0",
  "client": {
    "tlsEnable": true,
    "adminCredential": {
      "id": "exploreradmin",
      "password": "exploreradminpw"
    },
    "enableAuthentication": true,
    "organization": "${ORG1}",
    "connection": {
      "timeout": {
        "peer": {
          "endorser": "300"
        },
        "orderer": "300"
      }
    }
  },
  "channels": {
    "${CHANNEL_NAME}": {
      "peers": {
        "peer0-${ORG1}.${ORG1_DOMAIN}": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        },
        "peer0-${ORG2}.${ORG2_DOMAIN}": {
          "endorsingPeer": true,
          "chaincodeQuery": true,
          "ledgerQuery": true,
          "eventSource": true
        }
      }
    }
  },
  "organizations": {
    "${ORG1}": {
      "mspid": "${ORG1}MSP",
      "adminPrivateKey": {
        "path": "/tmp/crypto/organizations/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp/keystore/key.pem"
      },
      "peers": ["peer0-${ORG1}.${ORG1_DOMAIN}"],
      "signedCert": {
        "path": "/tmp/crypto/organizations/${ORG1}/users/Admin@${ORG1_DOMAIN}/msp/signcerts/Admin@${ORG1_DOMAIN}-cert.pem"
      }
    },
    "${ORG2}": {
      "mspid": "${ORG2}MSP",
      "adminPrivateKey": {
        "path": "/tmp/crypto/organizations/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp/keystore/key.pem"
      },
      "peers": ["peer0-${ORG2}.${ORG2_DOMAIN}"],
      "signedCert": {
        "path": "/tmp/crypto/organizations/${ORG2}/users/Admin@${ORG2_DOMAIN}/msp/signcerts/Admin@${ORG2_DOMAIN}-cert.pem"
      }
    }
  },
  "peers": {
    "peer0-${ORG1}.${ORG1_DOMAIN}": {
      "url": "grpcs://peer0-${ORG1}.${ORG1_DOMAIN}:7051",
      "tlsCACerts": {
        "path": "/tmp/crypto/organizations/${ORG1}/peers/peer0-${ORG1}.${ORG1_DOMAIN}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "peer0-${ORG1}.${ORG1_DOMAIN}",
        "hostnameOverride": "peer0-${ORG1}.${ORG1_DOMAIN}"
      }
    },
    "peer0-${ORG2}.${ORG2_DOMAIN}": {
      "url": "grpcs://peer0-${ORG2}.${ORG2_DOMAIN}:9051",
      "tlsCACerts": {
        "path": "/tmp/crypto/organizations/${ORG2}/peers/peer0-${ORG2}.${ORG2_DOMAIN}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "peer0-${ORG2}.${ORG2_DOMAIN}",
        "hostnameOverride": "peer0-${ORG2}.${ORG2_DOMAIN}"
      }
    }
  },
  "orderers": {
    "orderer.${ORDERER_DOMAIN}": {
      "url": "grpcs://orderer.${ORDERER_DOMAIN}:7050",
      "tlsCACerts": {
        "path": "/tmp/crypto/organizations/${ORDERER_ORG}/tls/ca.crt"
      },
      "grpcOptions": {
        "ssl-target-name-override": "orderer.${ORDERER_DOMAIN}",
        "hostnameOverride": "orderer.${ORDERER_DOMAIN}"
      }
    }
  }
}
EOF

# Create docker-compose-explorer.yaml
cat > "$PROJECT_NAME/docker/docker-compose-explorer.yaml" <<EOF
version: '3.8'

networks:
  ${NETWORK_NAME}:
    external: true

services:
  explorer-db:
    container_name: explorer-db
    image: hyperledger/explorer-db:latest
    environment:
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWORD=password
    ports:
      - "5432:5432"
    networks:
      - ${NETWORK_NAME}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hppoc -d fabricexplorer"]
      interval: 10s
      timeout: 5s
      retries: 5

  explorer:
    container_name: explorer
    image: hyperledger/explorer:latest
    environment:
      - DATABASE_HOST=explorer-db
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWORD=password
      - LOG_LEVEL_APP=debug
      - LOG_LEVEL_DB=debug
      - LOG_LEVEL_CONSOLE=debug
      - LOG_CONSOLE_STDOUT=true
      - DISCOVERY_AS_LOCALHOST=false
    volumes:
      - ${PWD}/${PROJECT_NAME}/explorer/config/config.json:/opt/explorer/app/platform/fabric/config.json
      - ${PWD}/${PROJECT_NAME}/explorer/connection-profile:/opt/explorer/app/platform/fabric/connection-profile
      - ${PWD}/${PROJECT_NAME}/explorer/crypto:/tmp/crypto
    ports:
      - "8080:8080"
    networks:
      - ${NETWORK_NAME}
    depends_on:
      explorer-db:
        condition: service_healthy
EOF

echo "Starting Explorer containers..."
cd "$PROJECT_NAME"
docker compose -f docker/docker-compose-explorer.yaml up -d
cd ..

echo "Waiting for Explorer to initialize (30s)..."
sleep 30

# Check status
echo ""
echo "=== Container Status ==="
docker ps | grep -E "explorer|explorer-db"

if docker ps | grep -q explorer; then
    echo ""
    echo "✅ Explorer started successfully!"
    
    # Get WSL IP address
    WSL_IP=$(ip addr show eth0 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ -z "$WSL_IP" ]; then
        WSL_IP="localhost"
    fi
    
    echo ""
    echo "=================================================="
    echo "✅ HYPERLEDGER EXPLORER IS RUNNING"
    echo "=================================================="
    echo ""
    echo "📊 Access Explorer from:"
    echo "   • WSL Terminal: curl http://localhost:8080"
    echo "   • Windows Browser: http://${WSL_IP}:8080"
    echo ""
    echo "=================================================="
    echo "🎉 DEPLOYMENT COMPLETE!"
    echo "=================================================="
    echo ""
    echo "Network Status:"
    echo "- Orderer (Raft): orderer.${ORDERER_DOMAIN}:7050"
    echo "- Peer Org1: peer0-${ORG1}.${ORG1_DOMAIN}:7051"
    echo "- Peer Org2: peer0-${ORG2}.${ORG2_DOMAIN}:9051"
    echo "- CouchDB Org1: http://localhost:5984"
    echo "- CouchDB Org2: http://localhost:6984"
    echo ""
    echo "Channel: ${CHANNEL_NAME}"
    echo "Chaincode: ${CHAINCODE_NAME} v${CHAINCODE_VERSION}"
    echo ""
    echo "Successful Transactions Demonstrated:"
    echo "1. Create Asset (asset100) from Org1 identity"
    echo "2. Create Asset (asset200) from Org2 identity"
    echo "3. Update Asset (asset100) from Org1 identity"
    echo "4. Query Asset (asset100) from Org2 identity"
    echo "5. GetAllAssets from Org1 identity"
    echo ""
    echo "Channel Config Update Demonstration: Modified batch timeout"
    echo ""
    echo "To view logs: docker logs -f explorer"
    echo "To stop network: docker compose -f ${PROJECT_NAME}/docker/docker-compose-*.yaml down"
    
else
    echo ""
    echo "❌ Explorer failed to start. Checking logs..."
    echo ""
    echo "=== Explorer DB Logs ==="
    docker logs explorer-db --tail 20
    echo ""
    echo "=== Explorer App Logs ==="
    docker logs explorer --tail 50
fi