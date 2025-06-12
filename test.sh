#!/bin/bash

# CharityChain Network Deployment with Fabric CAs - All-in-One Script
# This script sets up the Hyperledger Fabric network, generates identities,
# deploys the chaincode, and runs a simple test.

set -e

export DOCKER_DEFAULT_PLATFORM=linux/arm64

## Configuration
PROJECT_NAME="CharityChain-Network"
NETWORK_NAME="charitychain-net" # This is the Docker network name
CHANNEL_NAME="donationchannel"
CHAINCODE_NAME="donationcc"
CHAINCODE_VERSION="1.0"
CHAINCODE_SEQUENCE="1" 
CHAINCODE_LANG="node" # Assuming Node.js chaincode

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

# Docker image versions (Add if missing)
# FABRIC_CA_IMAGE="hyperledger/fabric-ca:1.5.7"
# FABRIC_ORDERER_IMAGE="hyperledger/fabric-orderer:2.5"
# FABRIC_PEER_IMAGE="hyperledger/fabric-peer:2.5"
# FABRIC_TOOLS_IMAGE="hyperledger/fabric-tools:2.5"

# Define paths to orderer and peer TLS CA certs inside CLI for convenience
ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/ca.crt"
CHARITY_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt"
DONOR_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls/ca.crt"


# --- Helper function to check if chaincode is already installed ---
check_chaincode_installed() {
    local PEER_ADDRESS=$1
    local TLS_ROOT_CERT_FILE=$2
    local ORG_MSP_ID=$3       # Optional: only for DonorOrg
    local ADMIN_MSP_PATH=$4   # Optional: only for DonorOrg

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
        # Default CLI context for CharityOrg
        installed_output=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "$PEER_ADDRESS" --tlsRootCertFiles "$TLS_ROOT_CERT_FILE" 2>&1)
    fi

    # Check for the specific label in the output
    echo "$installed_output" | grep -q "Label: ${CHAINCODE_NAME}_${CHAINCODE_VERSION}"
    if [ $? -eq 0 ]; then
        echo "Chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is already installed on ${PEER_ADDRESS}. Skipping installation."
        return 0 # Installed
    else
        echo "Chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is NOT installed on ${PEER_ADDRESS}."
        return 1 # Not installed
    fi
}
# --- End of Helper function ---


echo "=================================================="
echo "SECTION 6: CHAINCODE DEPLOYMENT"
echo "=================================================="

echo "Packaging chaincode '${CHAINCODE_NAME}'..."
# Chaincode is mounted at /opt/gopath/src/chaincode in CLI container
docker exec cli peer lifecycle chaincode package "${CHAINCODE_NAME}.tar.gz" \
  --path "/opt/gopath/src/chaincode/${CHAINCODE_NAME}" \
  --lang "$CHAINCODE_LANG" \
  --label "${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

echo "Installing chaincode on CharityOrg peer (peer0-${CHARITY_ORG}.${CHARITY_DOMAIN})..."
# Check if chaincode is already installed on CharityOrg peer
if ! check_chaincode_installed "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" "$CHARITY_PEER_TLS_CA_PATH_IN_CLI"; then
    docker exec cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"
fi

echo "Installing chaincode on DonorOrg peer (peer0-${DONOR_ORG}.${DONOR_DOMAIN})..."
# Check if chaincode is already installed on DonorOrg peer
if ! check_chaincode_installed "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" "$DONOR_PEER_TLS_CA_PATH_IN_CLI" "${DONOR_ORG}MSP" "/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp"; then
    docker exec \
      -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
      -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
      -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
      -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
      cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"
fi

echo "Querying installed chaincode on CharityOrg peer to get package ID..."
CC_PACKAGE_ID=""
MAX_QUERY_ATTEMPTS=10
CURRENT_ATTEMPT=0
while [ -z "$CC_PACKAGE_ID" ] && [ "$CURRENT_ATTEMPT" -lt "$MAX_QUERY_ATTEMPTS" ]; do
    CURRENT_ATTEMPT=$((CURRENT_ATTEMPT+1))
    sleep 3 # Wait for install to propagate or peer to be ready
    echo "Attempt $CURRENT_ATTEMPT/$MAX_QUERY_ATTEMPTS: Querying installed on peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}..." >&2
    set +e # Allow grep to fail without exiting script
    # Using default CLI context (CharityOrg)
    # MODIFIED: More robust package ID extraction
    CC_PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled \
        --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
        --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
        2>&1 | grep "Package ID:" | head -n 1 | awk -F': ' '{print $2}' | awk -F',' '{print $1}')
    set -e
    echo "Query attempt $CURRENT_ATTEMPT: Package ID found: '$CC_PACKAGE_ID'" >&2
done

if [ -z "$CC_PACKAGE_ID" ]; then
    echo "Error: Could not retrieve chaincode package ID from CharityOrg peer after $MAX_QUERY_ATTEMPTS attempts." >&2
    echo "Output of last queryinstalled:" >&2
    docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" >&2
    exit 1
fi
echo "Chaincode package ID: $CC_PACKAGE_ID"

echo "Approving chaincode definition for CharityOrg..."
docker exec \
  -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-charityOrg.charity.example.com:7051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" \
  --name "$CHAINCODE_NAME" \
  --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" \
  --sequence "$CHAINCODE_SEQUENCE" \
  --init-required \
  --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')"

echo "Approving chaincode definition for DonorOrg..."
docker exec \
  -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-donorOrg.donor.example.com:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode approveformyorg \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  --channelID "$CHANNEL_NAME" \
  --name "$CHAINCODE_NAME" \
  --version "$CHAINCODE_VERSION" \
  --package-id "$CC_PACKAGE_ID" \
  --sequence "$CHAINCODE_SEQUENCE" \
  --init-required \
  --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')"

echo "Verifying approval for CharityOrg..."
docker exec \
  -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-charityOrg.charity.example.com:7051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode queryapproved \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME"

echo "Verifying approval for DonorOrg..."
docker exec \
  -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-donorOrg.donor.example.com:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
  cli peer lifecycle chaincode queryapproved \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  --peerAddresses "peer0-donorOrg.donor.example.com:9051" \
  --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI"


echo "Waiting for approvals to propagate before checking commit readiness (5s)..."
sleep 15 # ADDED SLEEP

# =================================================================================
# --- CORRECTED LIFECYCLE SECTION (REPLACE THE OLD ONE WITH THIS) ---
# =================================================================================

echo "Waiting for approvals to propagate before checking commit readiness (5s)..."
sleep 5

echo "Checking commit readiness for chaincode '${CHAINCODE_NAME}' on channel '${CHANNEL_NAME}'..."
docker exec \
  -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-charityOrg.charity.example.com:7051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
  -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  cli peer lifecycle chaincode checkcommitreadiness \
  --channelID "$CHANNEL_NAME" \
  --name "$CHAINCODE_NAME" \
  --version "$CHAINCODE_VERSION" \
  --sequence "$CHAINCODE_SEQUENCE" \
  --init-required \
  --output json \
  --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')" # <-- FIX: Added signature policy to match what was approved.

# For CharityOrg
docker exec cli peer lifecycle chaincode queryapproved \
  -C $CHANNEL_NAME -n $CHAINCODE_NAME \
  --peerAddresses peer0-charityOrg.charity.example.com:7051 \
  --tlsRootCertFiles $CHARITY_PEER_TLS_CA_PATH_IN_CLI \
  --output json

# For DonorOrg
docker exec \
  -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-donorOrg.donor.example.com:9051" \
  cli peer lifecycle chaincode queryapproved \
  -C $CHANNEL_NAME -n $CHAINCODE_NAME \
  --output json

# For CharityOrg
docker exec cli peer lifecycle chaincode approveformyorg \
  -o orderer.orderer.example.com:7050 \
  --tls --cafile $ORDERER_CA_PATH_IN_CLI \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --package-id donationcc_1.0:81c49195b543055bf1bdab8a7c7516bec094543ebb9303ddb61e19c18608f908 \
  --sequence $CHAINCODE_SEQUENCE \
  --init-required \
  --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')"

# For DonorOrg
docker exec \
  -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
  -e CORE_PEER_ADDRESS="peer0-donorOrg.donor.example.com:9051" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
  cli peer lifecycle chaincode approveformyorg \
  -o orderer.orderer.example.com:7050 \
  --tls --cafile $ORDERER_CA_PATH_IN_CLI \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --package-id donationcc_1.0:81c49195b543055bf1bdab8a7c7516bec094543ebb9303ddb61e19c18608f908 \
  --sequence $CHAINCODE_SEQUENCE \
  --init-required \
  --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')"


echo "Committing chaincode definition with full endorsement..."
# Using CharityOrg context but specifying both peers
docker exec \
  -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
  -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
  cli peer lifecycle chaincode commit \
  -o orderer.orderer.example.com:7050 \
  --tls --cafile $ORDERER_CA_PATH_IN_CLI \
  --channelID $CHANNEL_NAME \
  --name $CHAINCODE_NAME \
  --version $CHAINCODE_VERSION \
  --sequence $CHAINCODE_SEQUENCE \
  --init-required \
  --peerAddresses peer0-charityOrg.charity.example.com:7051 \
  --tlsRootCertFiles $CHARITY_PEER_TLS_CA_PATH_IN_CLI \
  --waitForEvent
# =================================================================================
# --- END OF CORRECTED SECTION ---
# =================================================================================

# echo "Checking commit readiness for chaincode '${CHAINCODE_NAME}' on channel '${CHANNEL_NAME}'..."
# # Check from CharityOrg perspective (default CLI context)
# echo "Checking commit readiness from CharityOrg perspective..."
# docker exec \
#   -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
#   -e CORE_PEER_ADDRESS="peer0-charityOrg.charity.example.com:7051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode checkcommitreadiness \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
#   --version "$CHAINCODE_VERSION" --sequence "$CHAINCODE_SEQUENCE" \
#   --init-required --output json

# echo "Checking commit readiness from DonorOrg perspective..."
# docker exec \
#   -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
#   -e CORE_PEER_ADDRESS="peer0-donorOrg.donor.example.com:9051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode checkcommitreadiness \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
#   --version "$CHAINCODE_VERSION" --sequence "$CHAINCODE_SEQUENCE" \
#   --init-required --output json

# docker exec \
#   -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
#   -e CORE_PEER_ADDRESS="peer0-charityOrg.charity.example.com:7051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode commit \
#   -o "orderer.${ORDERER_DOMAIN}:7050" \
#   --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   --channelID "$CHANNEL_NAME" \
#   --name "$CHAINCODE_NAME" \
#   --version "$CHAINCODE_VERSION" \
#   --sequence "$CHAINCODE_SEQUENCE" \
#   --init-required \
#   --peerAddresses "peer0-charityOrg.charity.example.com:7051" \
#   --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   --peerAddresses "peer0-donorOrg.donor.example.com:9051" \
#   --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')" \
#   --waitForEvent


# # Optional: Check from DonorOrg perspective for thoroughness
# docker exec \
#   -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
#   -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode checkcommitreadiness \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
#   --sequence "$CHAINCODE_SEQUENCE" --init-required --output json \
#   --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" # ADDED PEER ADDRESSES for consistency

# sleep 2

# echo "Committing chaincode definition..."
# # Commit using CharityOrg's Admin context (default for CLI)
# # Must specify all endorsing peers that are part of the endorsement policy for this chaincode
# docker exec cli peer lifecycle chaincode commit \
#   -o "orderer.${ORDERER_DOMAIN}:7050" \
#   --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   --channelID "$CHANNEL_NAME" \
#   --name "$CHAINCODE_NAME" \
#   --version "$CHAINCODE_VERSION" \
#   --sequence "$CHAINCODE_SEQUENCE" \
#   --init-required \
#   --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   --signature-policy "AND('charityOrgMSP.peer','donorOrgMSP.peer')" \
#   --waitForEvent

echo "Querying committed chaincode definition on channel '${CHANNEL_NAME}'..."
# Query from one of the peers, e.g., CharityOrg's peer
docker exec cli peer lifecycle chaincode querycommitted \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI"

echo "Initializing chaincode (calling 'InitLedger')..."
# Invoke InitLedger. Ensure --isInit is used.
docker exec cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  --isInit \
  -c '{"Args":["InitLedger"]}' \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent # Optional: wait for the transaction to be committed

echo "Waiting for chaincode initialization transaction to complete (5s)..."
sleep 5

## --- SECTION 7: TESTING CHAINCODE ---
echo "=================================================="
echo "SECTION 7: TESTING CHAINCODE"
echo "=================================================="

echo "Querying all donations (should show initial ledger entry from InitLedger)..."
docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" -c '{"Args":["getAllDonations"]}'

echo "Creating a new donation: 'donation1'..."
docker exec cli peer chaincode invoke \
  -o "orderer.${ORDERER_DOMAIN}:7050" \
  --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["createDonation","donation1","donorA","100","charityX","2024-01-01T10:00:00Z"]}' \
  --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
  --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
  --waitForEvent

echo "Waiting for 'createDonation' invoke to complete (3s)..."
sleep 3

echo "Querying 'donation1'..."
docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" -c '{"Args":["queryDonation","donation1"]}'

echo "Querying all NFTs..."
docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" -c '{"Args":["getAllNFTs"]}'

echo "=================================================="
echo "CharityChain network deployment and basic test complete!"
echo "You can interact with the network using the 'cli' container:"
echo "  docker exec -it cli bash"
echo "To view logs of a specific container (e.g., orderer):"
echo "  docker logs -f orderer.${ORDERER_DOMAIN}"
echo "To view logs of CharityOrg peer:"
echo "  docker logs -f peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}"
echo "=================================================="