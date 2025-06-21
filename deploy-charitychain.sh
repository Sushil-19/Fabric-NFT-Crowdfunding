#!/bin/bash


set -e

## Configuration
PROJECT_NAME="CharityChain-Network"
NETWORK_NAME="charitychain-net" 
CHANNEL_NAME="donationchannel"
CHAINCODE_NAME="donationcc"
CHAINCODE_VERSION="1.0"
CHAINCODE_SEQUENCE="1"
CHAINCODE_LANG="node" 

# Organization details
ORDERER_ORG="ordererOrg"
ORDERER_DOMAIN="orderer.example.com"
CHARITY_ORG="charityOrg"
CHARITY_DOMAIN="charity.example.com"
DONOR_ORG="donorOrg"
DONOR_DOMAIN="donor.example.com"

# CA admin credentials
CA_ADMIN_USER="admin"
CA_ADMIN_PASS="adminpw"

# Docker image versions
FABRIC_CA_IMAGE="hyperledger/fabric-ca:1.5.7"
FABRIC_ORDERER_IMAGE="hyperledger/fabric-orderer:2.5"
FABRIC_PEER_IMAGE="hyperledger/fabric-peer:2.5"
FABRIC_TOOLS_IMAGE="hyperledger/fabric-tools:2.5"

## --- SECTION 1: CLEANUP AND DIRECTORY SETUP ---

echo "=================================================="
echo "SECTION 1: CLEANUP AND DIRECTORY SETUP"
echo "=================================================="

echo "Performing thorough cleanup of previous deployment..."
docker stop $(docker ps -a -q --filter ancestor="$FABRIC_CA_IMAGE" --filter ancestor="$FABRIC_ORDERER_IMAGE" --filter ancestor="$FABRIC_PEER_IMAGE" --filter ancestor="$FABRIC_TOOLS_IMAGE" --filter name="ca-${CHARITY_ORG}" --filter name="ca-${DONOR_ORG}" --filter name="orderer.${ORDERER_DOMAIN}" --filter name="peer0-${CHARITY_ORG}" --filter name="peer0-${DONOR_ORG}" --filter name="cli") 2>/dev/null || true
docker rm $(docker ps -a -q --filter ancestor="$FABRIC_CA_IMAGE" --filter ancestor="$FABRIC_ORDERER_IMAGE" --filter ancestor="$FABRIC_PEER_IMAGE" --filter ancestor="$FABRIC_TOOLS_IMAGE" --filter name="ca-${CHARITY_ORG}" --filter name="ca-${DONOR_ORG}" --filter name="orderer.${ORDERER_DOMAIN}" --filter name="peer0-${CHARITY_ORG}" --filter name="peer0-${DONOR_ORG}" --filter name="cli") 2>/dev/null || true

echo "Removing Docker networks..."
docker network rm "$NETWORK_NAME" 2>/dev/null || true

echo "Removing dangling Docker volumes (if any)..."
docker volume rm $(docker volume ls -qf dangling=true) 2>/dev/null || true

echo "Removing local deployment directories and files..."
if [ -d "$PROJECT_NAME" ]; then
    sudo rm -rf "$PROJECT_NAME"
fi
# Ensure this directory is completely gone before proceeding
if [ -d "$PROJECT_NAME" ]; then
    echo "Error: Failed to remove $PROJECT_NAME directory. Please remove it manually with sudo."
    exit 1
fi

echo "Pulling Docker images (amd64 for ARM emulation if needed)..."
docker pull --platform linux/amd64 "$FABRIC_CA_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_ORDERER_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_PEER_IMAGE" || true
docker pull --platform linux/amd64 "$FABRIC_TOOLS_IMAGE" || true

echo "Creating directory structure: $PROJECT_NAME/..."
mkdir -p "$PROJECT_NAME"/{organizations,configtx,docker,scripts,"chaincode/$CHAINCODE_NAME",channel-artifacts,system-genesis-block}
mkdir -p "$PROJECT_NAME/organizations/${CHARITY_ORG}"
mkdir -p "$PROJECT_NAME/organizations/${DONOR_ORG}"
mkdir -p "$PROJECT_NAME/organizations/${ORDERER_ORG}"


echo "Creating chaincode directory. Place your chaincode in: $PROJECT_NAME/chaincode/$CHAINCODE_NAME/"
mkdir -p "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/"
cat <<EOF > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/donationcc.js"
'use strict';

const { Contract } = require('fabric-contract-api');

class DonationContract extends Contract {

    async initLedger(ctx) {
        console.info('============= START : Init Ledger ===========');
        const donations = [
            {
                donationId: 'donation0',
                donorId: 'initialDonor',
                amount: '50',
                charityId: 'initialCharity',
                timestamp: '2023-01-01T00:00:00Z',
                nftId: 'nft0',
                docType: 'donation' 
            }
        ];

        for (const donation of donations) {
            await ctx.stub.putState(donation.donationId, Buffer.from(JSON.stringify(donation)));
            console.info(\`Donation \${donation.donationId} initialized\`);
        }
        console.info('============= END : Init Ledger ===========');
    }

    async createDonation(ctx, donationId, donorId, amount, charityId, timestamp) {
        const donation = {
            donationId,
            donorId,
            amount,
            charityId,
            timestamp,
            docType: 'donation', 
            nftId: \`nft-\${donationId}\` 
        };
        await ctx.stub.putState(donationId, Buffer.from(JSON.stringify(donation)));

        // Simulate NFT metadata creation
        const nftMetadata = {
            nftId: donation.nftId,
            donationId: donationId,
            donorId: donorId,
            amount: amount,
            charityId: charityId,
            timestamp: timestamp,
            description: \`A unique NFT representing a donation of \${amount} from \${donorId} to \${charityId}\`,
            image: "https://example.com/nft_image.png" 
        };
        await ctx.stub.putState(donation.nftId, Buffer.from(JSON.stringify(nftMetadata)));

        console.info(\`Donation \${donationId} created with NFT \${donation.nftId}\`);
        return JSON.stringify(donation);
    }

    async queryDonation(ctx, donationId) {
        const donationAsBytes = await ctx.stub.getState(donationId);
        if (!donationAsBytes || donationAsBytes.length === 0) {
            throw new Error(\`Donation \${donationId} does not exist\`);
        }
        console.log(donationAsBytes.toString());
        return donationAsBytes.toString();
    }

    async getAllDonations(ctx) {
        const allResults = [];
        // range query with empty string for startKey and endKey does an open-ended query of all records in the chaincode namespace.
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
            // Ensure we only pick up actual donation records, not NFTs or other data types
            if (record.docType === 'donation') {
                allResults.push(record);
            }
            result = await iterator.next();
        }
        return JSON.stringify(allResults);
    }

    async getAllNFTs(ctx) {
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
            if (record.nftId && record.docType !== 'donation') { // NFT metadata will have nftId but not docType 'donation'
                allResults.push(record);
            }
            result = await iterator.next();
        }
        return JSON.stringify(allResults);
    }
}

module.exports = DonationContract;
EOF

cat <<EOF > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/index.js"
'use strict';

const DonationContract = require('./donationcc.js');

module.exports.contracts = [DonationContract];
EOF

cat <<EOF > "$PROJECT_NAME/chaincode/$CHAINCODE_NAME/package.json"
{
  "name": "donationcc",
  "version": "1.0.0",
  "description": "Donation Chaincode for CharityChain Network",
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
  - &${CHARITY_ORG}
    Name: ${CHARITY_ORG}
    ID: ${CHARITY_ORG}MSP
    MSPDir: ../organizations/${CHARITY_ORG}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('${CHARITY_ORG}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('${CHARITY_ORG}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('${CHARITY_ORG}MSP.admin')"
    AnchorPeers:
      - Host: peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}
        Port: 7051
  - &${DONOR_ORG}
    Name: ${DONOR_ORG}
    ID: ${DONOR_ORG}MSP
    MSPDir: ../organizations/${DONOR_ORG}/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('${DONOR_ORG}MSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('${DONOR_ORG}MSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('${DONOR_ORG}MSP.admin')"
    AnchorPeers:
      - Host: peer0-${DONOR_ORG}.${DONOR_DOMAIN}
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
  OrdererType: solo
  Addresses:
    - orderer.${ORDERER_DOMAIN}:7050
  BatchTimeout: 2s
  BatchSize:
    MaxMessageCount: 10
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 512 KB
  Organizations: # To be specified in profile
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
    BlockValidation: # Used by the orderer system channel
      Type: ImplicitMeta
      Rule: "ANY Writers" # Default policy
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
      Rule: "OR('charityOrgMSP.member', 'donorOrgMSP.member')"
    Endorsement:
      Type: Signature
      Rule: "OR('charityOrgMSP.member', 'donorOrgMSP.member')"
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
          - *${CHARITY_ORG}
          - *${DONOR_ORG}
  TwoOrgsChannel:
    Consortium: SampleConsortium
    <<: *ChannelDefaults
    Application:
      <<: *ApplicationDefaults
      Organizations:
        - *${CHARITY_ORG}
        - *${DONOR_ORG}
      Capabilities:
        <<: *ApplicationCapabilities
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
    platform: linux/amd64 # Specify platform for consistency
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
      - ORDERER_KAFKA_TOPIC_REPLICATIONFACTOR=1 # For solo orderer (though Kafka itself is not used in solo)
      - ORDERER_KAFKA_VERBOSE=true # For solo orderer
      # For Fabric 2.x, these cluster env vars are needed even for a single solo orderer
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
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
version: '2.4' # Specifying a version that supports 'depends_on' and 'networks'
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
      - ORDERER_GENERAL_TLS_ROOTCAS=/var/hyperledger/orderer/tls/ca.crt # Corrected: Removed square brackets
      - ORDERER_KAFKA_TOPIC_REPLICATIONFACTOR=1
      - ORDERER_KAFKA_VERBOSE=true
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=/var/hyperledger/orderer/tls/ca.crt # Corrected: Removed square brackets
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

  ca-${CHARITY_ORG}.${CHARITY_DOMAIN}:
    container_name: ca-${CHARITY_ORG}.${CHARITY_DOMAIN}
    image: ${FABRIC_CA_IMAGE}
    platform: linux/amd64
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${CHARITY_ORG}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_PORT=7054
      - FABRIC_CA_SERVER_CSR_HOSTS=ca-${CHARITY_ORG}.${CHARITY_DOMAIN},localhost
      - FABRIC_CA_SERVER_DEBUG=true
    ports:
      - "7054:7054"
    command: sh -c 'fabric-ca-server start -b ${CA_ADMIN_USER}:${CA_ADMIN_PASS} -d'
    volumes:
      - ../organizations/${CHARITY_ORG}/ca:/etc/hyperledger/fabric-ca-server
      - ../organizations:/etc/hyperledger/fabric-ca-server/organizations
    networks:
      - ${NETWORK_NAME}

  peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:
    container_name: peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}
    image: ${FABRIC_PEER_IMAGE}
    platform: linux/amd64
    environment:
      - CORE_VM_ENDPOINT=unix:///var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${NETWORK_NAME}
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}
      - CORE_PEER_ADDRESS=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051
      - CORE_PEER_LISTENADDRESS=0.0.0.0:7051
      - CORE_PEER_CHAINCODEADDRESS=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7052
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051
      - CORE_PEER_LOCALMSPID=${CHARITY_ORG}MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_OPERATIONS_LISTENADDRESS=0.0.0.0:9443
      - CORE_METRICS_PROVIDER=prometheus
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ../organizations/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/msp:/etc/hyperledger/fabric/msp
      - ../organizations/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls:/etc/hyperledger/fabric/tls
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    ports:
      - 7051:7051
      - 9443:9443
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - ca-${CHARITY_ORG}.${CHARITY_DOMAIN}

  ca-${DONOR_ORG}.${DONOR_DOMAIN}:
    container_name: ca-${DONOR_ORG}.${DONOR_DOMAIN}
    image: ${FABRIC_CA_IMAGE}
    platform: linux/amd64
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${DONOR_ORG}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_PORT=8054
      - FABRIC_CA_SERVER_CSR_HOSTS=ca-${DONOR_ORG}.${DONOR_DOMAIN},localhost
      - FABRIC_CA_SERVER_DEBUG=true
    ports:
      - "8054:8054"
    command: sh -c 'fabric-ca-server start -b ${CA_ADMIN_USER}:${CA_ADMIN_PASS} -d'
    volumes:
      - ../organizations/${DONOR_ORG}/ca:/etc/hyperledger/fabric-ca-server
      - ../organizations:/etc/hyperledger/fabric-ca-server/organizations
    networks:
      - ${NETWORK_NAME}

  peer0-${DONOR_ORG}.${DONOR_DOMAIN}:
    container_name: peer0-${DONOR_ORG}.${DONOR_DOMAIN}
    image: ${FABRIC_PEER_IMAGE}
    platform: linux/amd64
    environment:
      - CORE_VM_ENDPOINT=unix:///var/run/docker.sock
      - CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${NETWORK_NAME}
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=peer0-${DONOR_ORG}.${DONOR_DOMAIN}
      - CORE_PEER_ADDRESS=peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051
      - CORE_PEER_LISTENADDRESS=0.0.0.0:9051
      - CORE_PEER_CHAINCODEADDRESS=peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9052
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:9052
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051
      - CORE_PEER_LOCALMSPID=${DONOR_ORG}MSP
      - CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/msp
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_PEER_OPERATIONS_LISTENADDRESS=0.0.0.0:9444
      - CORE_METRICS_PROVIDER=prometheus
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ../organizations/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/msp:/etc/hyperledger/fabric/msp
      - ../organizations/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls:/etc/hyperledger/fabric/tls
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    ports:
      - 9051:9051
      - 9444:9444
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - ca-${DONOR_ORG}.${DONOR_DOMAIN}

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
      - CORE_PEER_ADDRESS=peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051
      - CORE_PEER_LOCALMSPID=${CHARITY_ORG}MSP
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_ROOTCERT_FILE=/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/users/Admin@${CHARITY_DOMAIN}/msp
      - ORDERER_CA=/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/tls/ca.crt
    working_dir: /opt/peer
    command: /bin/bash
    volumes:
      - ../chaincode:/opt/gopath/src/chaincode
      - /var/run/docker.sock:/var/run/docker.sock # CORRECTED LINE
      - ../organizations:/opt/hyperledger/fabric/crypto
      - ../channel-artifacts:/opt/hyperledger/fabric/channel-artifacts
      - ../scripts:/opt/hyperledger/fabric/scripts
      - ../system-genesis-block:/opt/hyperledger/fabric/system-genesis-block
    networks:
      - ${NETWORK_NAME}
    depends_on:
      - orderer.${ORDERER_DOMAIN}
      - peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}
      - peer0-${DONOR_ORG}.${DONOR_DOMAIN}
EOF

cat > "$PROJECT_NAME/docker/docker-compose.yaml" <<EOF
networks:
  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
EOF

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
# $1: Org Name (e.g., charityOrg)
# $2: Org Domain (e.g., charity.example.com)
# $3: Identity Type (peer, orderer, user, admin)
# $4: Identity Short Name (e.g., peer0-charityOrg, orderer, User1)
# $5: Identity Password (defaults to "password")
# $6: CA Port (e.g., 7054)
# $7: CA Container Name (e.g., ca-charityOrg.charity.example.com)
# $8: Path to CA's own TLS root cert *inside the CA container*
# $9: Custom Affiliation or Attributes
# $10: (Optional) The actual name of the CA to use for registration (e.g., ca-charityOrg)
function register_enroll {
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
    CA_ADMIN_HOME_IN_CA="/etc/hyperledger/fabric/organizations/${CHARITY_ORG}/users/${CA_ADMIN_USER}@${CHARITY_DOMAIN}"
  fi

  docker exec \
    -e FABRIC_CA_CLIENT_HOME="$CA_ADMIN_HOME_IN_CA" \
    "${CA_CONTAINER_TO_USE}" fabric-ca-client register \
    --caname "${CA_NAME_TO_USE}" \
    --id.name "${IDENTITY_FULL_NAME}" \
    --id.secret "${IDENTITY_PASS}" \
    --id.type "${IDENTITY_TYPE}" \
    --id.attrs "${IDENTITY_ATTRS_STR}" \
    --tls.certfiles "$CONTAINER_CA_TLS_CERT_PATH"

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
    "mv \"$ADMIN_MSP_HOME_IN_CA/msp/keystore\"/* \"$ADMIN_MSP_HOME_IN_CA/msp/keystore/key.pem\""

  echo "Copying CA admin's MSP from CA container to host for ${ORG_NAME}..."
  local HOST_ADMIN_MSP_PATH="$PROJECT_NAME/organizations/${ORG_NAME}/users/${CA_ADMIN_USER}@${ORG_DOMAIN}/msp"
  mkdir -p "$HOST_ADMIN_MSP_PATH"
  docker cp "${CA_CONTAINER_TO_USE}:${ADMIN_MSP_HOME_IN_CA}/msp/." "$HOST_ADMIN_MSP_PATH"
}

# Function to create the basic MSP directory structure for an organization
# and fetch its CA's root signing certificate.
# $1: Org Name (e.g., charityOrg)
# $2: Org Domain (e.g., charity.example.com)
# $3: Port of the CA server this org will use (e.g., 7054)
# $4: Name of the CA container for this org (e.g., ca-charityOrg.charity.example.com)
# Returns: Path to the CA's own TLS certificate *inside the CA container*
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


    echo "Fetching CA root signing cert for $org's MSP and placing in cacerts and tlscacerts..." >&2
    FABRIC_CA_CLIENT_HOME="$host_org_base_dir" fabric-ca-client getcacert \
        -u "https://localhost:$ca_port_for_getcacert" \
        --tls.certfiles "$host_storage_for_ca_tls_cert" \
        -M "$host_org_msp_dir" 

    local retrieved_ca_signing_cert_filename="localhost-${ca_port_for_getcacert}.pem"
    if [ ! -f "$host_org_msp_dir/cacerts/$retrieved_ca_signing_cert_filename" ]; then
        echo "Error: Failed to retrieve CA root signing cert for $org. File not found: $host_org_msp_dir/cacerts/$retrieved_ca_signing_cert_filename" >&2
        ls -l "$host_org_msp_dir/cacerts/" 
        exit 1
    fi

    cp "$host_org_msp_dir/cacerts/$retrieved_ca_signing_cert_filename" \
       "$host_org_msp_dir/tlscacerts/tlsca.$domain-cert.pem"

    echo "Creating config.yaml for $org's MSP..." >&2
    cat > "$host_org_msp_dir/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_filename}
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_filename}
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_filename}
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${retrieved_ca_signing_cert_filename}
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
        --tls.certfiles "$path_to_ca_tls_cert_in_container"
    local exit_code=$?
    set -e 

    if [ $exit_code -ne 0 ]; then
        echo "Warning: Adding affiliation '$affiliation_to_register' resulted in exit code $exit_code. It might already exist or another error occurred. Continuing." >&2
    else
        echo "Affiliation '$affiliation_to_register' added successfully or already existed." >&2
    fi
}


## --- SECTION 4: NETWORK SETUP AND IDENTITY GENERATION ---

echo "=================================================="
echo "SECTION 4: NETWORK SETUP AND IDENTITY GENERATION"
echo "=================================================="

echo "Creating Docker network: $NETWORK_NAME"
docker network create "$NETWORK_NAME" || true # Allow if already exists

echo "Starting CAs..."
docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" up -d "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" "ca-${DONOR_ORG}.${DONOR_DOMAIN}"
echo "Waiting for CAs to start (increase if needed, currently 15s)..."

sleep 15

echo "Creating organization MSP structures and enrolling CA admin users..."

CHARITY_CA_INTERNAL_TLS_CERT_PATH=$(create_msp_structure "$CHARITY_ORG" "$CHARITY_DOMAIN" 7054 "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}")
enroll_ca_admin "$CHARITY_ORG" "$CHARITY_DOMAIN" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" 7054 "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" "$CHARITY_CA_INTERNAL_TLS_CERT_PATH"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/users/$CA_ADMIN_USER@$CHARITY_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/admincerts/"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$CHARITY_ORG/users/$CA_ADMIN_USER@$CHARITY_DOMAIN/msp/"
cp -R "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/cacerts/." "$PROJECT_NAME/organizations/$CHARITY_ORG/users/$CA_ADMIN_USER@$CHARITY_DOMAIN/msp/cacerts/"


DONOR_CA_INTERNAL_TLS_CERT_PATH=$(create_msp_structure "$DONOR_ORG" "$DONOR_DOMAIN" 8054 "ca-${DONOR_ORG}.${DONOR_DOMAIN}")
enroll_ca_admin "$DONOR_ORG" "$DONOR_DOMAIN" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" 8054 "ca-${DONOR_ORG}.${DONOR_DOMAIN}" "$DONOR_CA_INTERNAL_TLS_CERT_PATH"
cp "$PROJECT_NAME/organizations/$DONOR_ORG/users/$CA_ADMIN_USER@$DONOR_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$DONOR_ORG/msp/admincerts/"
cp "$PROJECT_NAME/organizations/$DONOR_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$DONOR_ORG/users/$CA_ADMIN_USER@$DONOR_DOMAIN/msp/"
cp -R "$PROJECT_NAME/organizations/$DONOR_ORG/msp/cacerts/." "$PROJECT_NAME/organizations/$DONOR_ORG/users/$CA_ADMIN_USER@$DONOR_DOMAIN/msp/cacerts/"

ORDERER_ISSUING_CA_NAME="ca-${CHARITY_ORG}.${CHARITY_DOMAIN}"
ORDERER_ISSUING_CA_PORT=7054
ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH="$CHARITY_CA_INTERNAL_TLS_CERT_PATH"
create_msp_structure "$ORDERER_ORG" "$ORDERER_DOMAIN" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_NAME"
echo "Registering affiliations..."
register_affiliation "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" 7054 "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "$CHARITY_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" 7054 "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "$CHARITY_ORG.peer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" 7054 "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "$CHARITY_ORG.user" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" 7054 "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "$CHARITY_ORG.admin" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"

register_affiliation "ca-${DONOR_ORG}.${DONOR_DOMAIN}" 8054 "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "$DONOR_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${DONOR_ORG}.${DONOR_DOMAIN}" 8054 "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "$DONOR_ORG.peer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${DONOR_ORG}.${DONOR_DOMAIN}" 8054 "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "$DONOR_ORG.user" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "ca-${DONOR_ORG}.${DONOR_DOMAIN}" 8054 "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "$DONOR_ORG.admin" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"

register_affiliation "$ORDERER_ISSUING_CA_NAME" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" "$ORDERER_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
register_affiliation "$ORDERER_ISSUING_CA_NAME" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" "$ORDERER_ORG.orderer" "$CA_ADMIN_USER" "$CA_ADMIN_PASS"
echo "Registering and enrolling identities for nodes and users..."

register_enroll "$CHARITY_ORG" "$CHARITY_DOMAIN" peer "peer0-${CHARITY_ORG}" "${CA_ADMIN_PASS}" 7054 "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=peer"
echo "Populating peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$CHARITY_ORG/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/msp/"
mkdir -p "$PROJECT_NAME/organizations/$CHARITY_ORG/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/msp/admincerts"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/users/Admin@$CHARITY_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$CHARITY_ORG/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/msp/admincerts/"

register_enroll "$CHARITY_ORG" "$CHARITY_DOMAIN" user "User1" "${CA_ADMIN_PASS}" 7054 "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=client"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$CHARITY_ORG/users/User1@$CHARITY_DOMAIN/msp/"
mkdir -p "$PROJECT_NAME/organizations/$CHARITY_ORG/users/User1@$CHARITY_DOMAIN/msp/cacerts"
cp -R "$PROJECT_NAME/organizations/$CHARITY_ORG/msp/cacerts/." "$PROJECT_NAME/organizations/$CHARITY_ORG/users/User1@$CHARITY_DOMAIN/msp/cacerts/"

register_enroll "$DONOR_ORG" "$DONOR_DOMAIN" peer "peer0-${DONOR_ORG}" "${CA_ADMIN_PASS}" 8054 "ca-${DONOR_ORG}.${DONOR_DOMAIN}" "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=peer"
echo "Populating peer0-${DONOR_ORG}.${DONOR_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$DONOR_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$DONOR_ORG/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/msp/"
mkdir -p "$PROJECT_NAME/organizations/$DONOR_ORG/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/msp/admincerts"
cp "$PROJECT_NAME/organizations/$DONOR_ORG/users/Admin@$DONOR_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$DONOR_ORG/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/msp/admincerts/"

register_enroll "$DONOR_ORG" "$DONOR_DOMAIN" user "User1" "${CA_ADMIN_PASS}" 8054 "ca-${DONOR_ORG}.${DONOR_DOMAIN}" "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "hf.Registrar.Roles=client"
cp "$PROJECT_NAME/organizations/$DONOR_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$DONOR_ORG/users/User1@$DONOR_DOMAIN/msp/"
mkdir -p "$PROJECT_NAME/organizations/$DONOR_ORG/users/User1@$DONOR_DOMAIN/msp/cacerts"
cp -R "$PROJECT_NAME/organizations/$DONOR_ORG/msp/cacerts/." "$PROJECT_NAME/organizations/$DONOR_ORG/users/User1@$DONOR_DOMAIN/msp/cacerts/"

register_enroll "$ORDERER_ORG" "$ORDERER_DOMAIN" orderer "orderer" \
  "${CA_ADMIN_PASS}" "$ORDERER_ISSUING_CA_PORT" "$ORDERER_ISSUING_CA_NAME" \
  "$ORDERER_ISSUING_CA_INTERNAL_TLS_CERT_PATH" \
  "affiliation=${ORDERER_ORG}.orderer" \
  "ca-${CHARITY_ORG}"

echo "Populating orderer.${ORDERER_DOMAIN}'s local MSP with admin cert and config..."
cp "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/config.yaml" "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/admincerts"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/users/$CA_ADMIN_USER@$CHARITY_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN/msp/admincerts/"
echo "Populating OrdererOrg's main MSP and TLS directories from enrolled orderer identity..."

ORDERER_NODE_CRYPTO_BASE_PATH="$PROJECT_NAME/organizations/$ORDERER_ORG/orderers/orderer.$ORDERER_DOMAIN"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/signcerts"

cp "$ORDERER_NODE_CRYPTO_BASE_PATH/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/signcerts/"
cp "$PROJECT_NAME/organizations/$CHARITY_ORG/users/Admin@$CHARITY_DOMAIN/msp/signcerts"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/admincerts/"
mkdir -p "$PROJECT_NAME/organizations/$ORDERER_ORG/tls"

cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/ca.crt" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/ca.crt"
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/server.crt" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/server.crt"
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/tls/server.key" "$PROJECT_NAME/organizations/$ORDERER_ORG/tls/server.key"
cp "$ORDERER_NODE_CRYPTO_BASE_PATH/msp/keystore"/* "$PROJECT_NAME/organizations/$ORDERER_ORG/msp/keystore/"

echo "Generating genesis block (system channel)..."
export FABRIC_CFG_PATH="$PWD/$PROJECT_NAME/configtx"
configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock "$PROJECT_NAME/system-genesis-block/genesis.block"

echo "Generating channel configuration transaction for '${CHANNEL_NAME}'..."
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx "$PROJECT_NAME/channel-artifacts/$CHANNEL_NAME.tx" -channelID "$CHANNEL_NAME"
echo "Generating anchor peer update transactions..."

configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate "$PROJECT_NAME/channel-artifacts/${CHARITY_ORG}Anchor.tx" -channelID "$CHANNEL_NAME" -asOrg "$CHARITY_ORG"
configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate "$PROJECT_NAME/channel-artifacts/${DONOR_ORG}Anchor.tx" -channelID "$CHANNEL_NAME" -asOrg "$DONOR_ORG"

echo "Starting orderer, peer, and CLI containers..."
docker compose -f "$PROJECT_NAME/docker/docker-compose-orderer.yaml" up -d
docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" up -d peer0-${CHARITY_ORG}.${CHARITY_DOMAIN} peer0-${DONOR_ORG}.${DONOR_DOMAIN} cli

echo "Starting orderer, peer, and CLI containers..."
docker compose -f "$PROJECT_NAME/docker/docker-compose-peers.yaml" up -d orderer.${ORDERER_DOMAIN} peer0-${CHARITY_ORG}.${CHARITY_DOMAIN} peer0-${DONOR_ORG}.${DONOR_DOMAIN} cli

register_affiliation "ca-${CHARITY_ORG}.${CHARITY_DOMAIN}" 7054 "$CHARITY_CA_INTERNAL_TLS_CERT_PATH" "$CHARITY_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$CHARITY_ORG"
register_affiliation "ca-${DONOR_ORG}.${DONOR_DOMAIN}" 8054 "$DONOR_CA_INTERNAL_TLS_CERT_PATH" "$DONOR_ORG" "$CA_ADMIN_USER" "$CA_ADMIN_PASS" "$DONOR_ORG"

echo "Waiting for network components to initialize (currently 20s)..."
sleep 20

## --- SECTION 5: CHANNEL OPERATIONS ---
echo "=================================================="
echo "SECTION 5: CHANNEL OPERATIONS"
echo "=================================================="

ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/tls/ca.crt"

echo "Creating channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${CHARITY_ORG}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/users/Admin@${CHARITY_DOMAIN}/msp" \
  cli peer channel create \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "$CHANNEL_NAME" \
  -f "/opt/hyperledger/fabric/channel-artifacts/$CHANNEL_NAME.tx" \
  --outputBlock "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"

echo "Joining CharityOrg peer (peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}) to channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${CHARITY_ORG}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/users/Admin@${CHARITY_DOMAIN}/msp" \
  -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt" \
  cli peer channel join -b "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block"

echo "Joining DonorOrg peer (peer0-${DONOR_ORG}.${DONOR_DOMAIN}) to channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls/ca.crt" \
  cli peer channel join -b "/opt/hyperledger/fabric/channel-artifacts/${CHANNEL_NAME}.block"

echo "Updating anchor peers for CharityOrg on channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${CHARITY_ORG}MSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/users/Admin@${CHARITY_DOMAIN}/msp" \
  -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt" \
  cli peer channel update \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "${CHANNEL_NAME}" \
  -f "/opt/hyperledger/fabric/channel-artifacts/${CHARITY_ORG}Anchor.tx" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"

echo "Updating anchor peers for DonorOrg on channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls/ca.crt" \
  cli peer channel update \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  -c "${CHANNEL_NAME}" \
  -f "/opt/hyperledger/fabric/channel-artifacts/${DONOR_ORG}Anchor.tx" \
  --tls \
  --cafile "$ORDERER_CA_PATH_IN_CLI"
  

ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/ca.crt"
CHARITY_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt"
DONOR_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls/ca.crt"


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


# --- Helper function to check if chaincode is already installed ---
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

echo "=================================================="
echo "SECTION 6: CHAINCODE DEPLOYMENT"
echo "=================================================="

echo "Packaging chaincode '${CHAINCODE_NAME}'..."
docker exec cli peer lifecycle chaincode package "${CHAINCODE_NAME}.tar.gz" \
  --path "/opt/gopath/src/chaincode/${CHAINCODE_NAME}" \
  --lang "$CHAINCODE_LANG" \
  --label "${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

echo "Installing chaincode on CharityOrg peer..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

echo "Installing chaincode on DonorOrg peer..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

echo "Querying installed chaincode on CharityOrg peer to get package ID..."
CC_PACKAGE_ID=""
MAX_ATTEMPTS=5
for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
    echo "Attempt ${i}/${MAX_ATTEMPTS}..."
    set +e
    CC_PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" 2>/dev/null | grep "Package ID:" | sed -n 's/Package ID: \(.*\), Label:.*/\1/p')
    set -e
    if [ -n "$CC_PACKAGE_ID" ]; then
        echo "Successfully retrieved Package ID: ${CC_PACKAGE_ID}"
        break
    fi
    echo "Failed to retrieve Package ID. Retrying in 3 seconds..."
    sleep 3
done

if [ -z "$CC_PACKAGE_ID" ]; then
    echo "Error: Could not retrieve chaincode package ID from CharityOrg peer."
    exit 1
fi

echo "Approving chaincode definition for CharityOrg..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')"

echo "Approving chaincode definition for DonorOrg..."
docker exec \
  -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
  -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')"

echo "Checking commit readiness..."
docker exec \
  -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode checkcommitreadiness \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')" --output json

echo "Committing chaincode definition..."
docker exec \
  cli peer lifecycle chaincode commit \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --sequence "$CHAINCODE_SEQUENCE" --init-required \
  --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')" \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI"

echo "Querying committed chaincode definition..."
docker exec \
  cli peer lifecycle chaincode querycommitted \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI"

echo "Initializing chaincode (calling 'InitLedger')..."
docker exec cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" --isInit \
  -c '{"Args":["initLedger"]}' \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

echo "Waiting for chaincode initialization to complete (5s)..."
sleep 5