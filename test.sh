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

# Define paths to orderer and peer TLS CA certs inside CLI for convenience
ORDERER_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${ORDERER_ORG}/orderers/orderer.${ORDERER_DOMAIN}/tls/ca.crt"
CHARITY_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${CHARITY_ORG}/peers/peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}/tls/ca.crt"
DONOR_PEER_TLS_CA_PATH_IN_CLI="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/peers/peer0-${DONOR_ORG}.${DONOR_DOMAIN}/tls/ca.crt"


# # --- Helper function to check if chaincode is already installed ---
# check_chaincode_installed() {
#     local PEER_ADDRESS=$1
#     local TLS_ROOT_CERT_FILE=$2
#     local ORG_MSP_ID=$3       
#     local ADMIN_MSP_PATH=$4   

#     echo "Checking if chaincode '${CHAINCODE_NAME}_${CHAINCODE_VERSION}' is installed on ${PEER_ADDRESS}..."

#     local installed_output
#     if [ -n "$ORG_MSP_ID" ] && [ -n "$ADMIN_MSP_PATH" ]; then
#         installed_output=$(docker exec \
#             -e CORE_PEER_LOCALMSPID="$ORG_MSP_ID" \
#             -e CORE_PEER_ADDRESS="$PEER_ADDRESS" \
#             -e CORE_PEER_MSPCONFIGPATH="$ADMIN_MSP_PATH" \
#             -e CORE_PEER_TLS_ROOTCERT_FILE="$TLS_ROOT_CERT_FILE" \
#             cli peer lifecycle chaincode queryinstalled --peerAddresses "$PEER_ADDRESS" --tlsRootCertFiles "$TLS_ROOT_CERT_FILE" 2>&1)
#     else
#         installed_output=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "$PEER_ADDRESS" --tlsRootCertFiles "$TLS_ROOT_CERT_FILE" 2>&1)
#     fi

#     echo "$installed_output" | grep -q "Label: ${CHAINCODE_NAME}_${CHAINCODE_VERSION}"
# }

# # --- Helper function to verify a donation query ---
# verify_donation() {
#     local DONATION_ID=$1
#     echo "Verifying donation '$DONATION_ID' by querying..."
#     QUERY_RESULT=$(docker exec cli peer chaincode query \
#       -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" -c "{\"Args\":[\"queryDonation\",\"$DONATION_ID\"]}")
    
#     if echo "$QUERY_RESULT" | grep -q "\"donationId\":\"$DONATION_ID\""; then
#         echo "Donation '$DONATION_ID' successfully queried and found."
#     else
#         echo "Error: Donation '$DONATION_ID' not found or query failed."
#         echo "Query Result: $QUERY_RESULT"
#         exit 1
#     fi
# }


# echo "=================================================="
# echo "SECTION 6: CHAINCODE DEPLOYMENT"
# echo "=================================================="

# echo "Packaging chaincode '${CHAINCODE_NAME}'..."
# docker exec cli peer lifecycle chaincode package "${CHAINCODE_NAME}.tar.gz" \
#   --path "/opt/gopath/src/chaincode/${CHAINCODE_NAME}" \
#   --lang "$CHAINCODE_LANG" \
#   --label "${CHAINCODE_NAME}_${CHAINCODE_VERSION}"

# echo "Installing chaincode on CharityOrg peer..."
# docker exec \
#   -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

# echo "Installing chaincode on DonorOrg peer..."
# docker exec \
#   -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
#   -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode install "${CHAINCODE_NAME}.tar.gz"

# echo "Querying installed chaincode on CharityOrg peer to get package ID..."
# CC_PACKAGE_ID=""
# MAX_ATTEMPTS=5
# for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
#     echo "Attempt ${i}/${MAX_ATTEMPTS}..."
#     set +e
#     CC_PACKAGE_ID=$(docker exec cli peer lifecycle chaincode queryinstalled --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" 2>/dev/null | grep "Package ID:" | sed -n 's/Package ID: \(.*\), Label:.*/\1/p')
#     set -e
#     if [ -n "$CC_PACKAGE_ID" ]; then
#         echo "Successfully retrieved Package ID: ${CC_PACKAGE_ID}"
#         break
#     fi
#     echo "Failed to retrieve Package ID. Retrying in 3 seconds..."
#     sleep 3
# done

# if [ -z "$CC_PACKAGE_ID" ]; then
#     echo "Error: Could not retrieve chaincode package ID from CharityOrg peer."
#     exit 1
# fi

# echo "Approving chaincode definition for CharityOrg..."
# docker exec \
#   -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode approveformyorg \
#   -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
#   --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
#   --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')"

# echo "Approving chaincode definition for DonorOrg..."
# docker exec \
#   -e CORE_PEER_LOCALMSPID="${DONOR_ORG}MSP" \
#   -e CORE_PEER_ADDRESS="peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" \
#   -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/${DONOR_ORG}/users/Admin@${DONOR_DOMAIN}/msp" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode approveformyorg \
#   -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
#   --package-id "$CC_PACKAGE_ID" --sequence "$CHAINCODE_SEQUENCE" --init-required \
#   --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')"

# echo "Checking commit readiness..."
# docker exec \
#   -e CORE_PEER_ADDRESS="peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" \
#   -e CORE_PEER_TLS_ROOTCERT_FILE="$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   cli peer lifecycle chaincode checkcommitreadiness \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
#   --sequence "$CHAINCODE_SEQUENCE" --init-required \
#   --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')" --output json

# echo "Committing chaincode definition..."
# docker exec \
#   cli peer lifecycle chaincode commit \
#   -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
#   --sequence "$CHAINCODE_SEQUENCE" --init-required \
#   --signature-policy "AND('${CHARITY_ORG}MSP.peer','${DONOR_ORG}MSP.peer')" \
#   --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI"

# echo "Querying committed chaincode definition..."
# docker exec \
#   cli peer lifecycle chaincode querycommitted \
#   --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" \
#   --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI"

# echo "Initializing chaincode (calling 'InitLedger')..."
# docker exec cli peer chaincode invoke \
#   -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
#   -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" --isInit \
#   -c '{"Args":["initLedger"]}' \
#   --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
#   --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
#   --waitForEvent

# echo "Waiting for chaincode initialization to complete (5s)..."
# sleep 5

## --- SECTION 7: TESTING CHAINCODE ---
echo "=================================================="
echo "SECTION 7: TESTING CHAINCODE"
echo "=================================================="

# Query all donations initially (should show only initLedger entry)
echo "Querying all donations (should show initial ledger entry 'donation0')..."
docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" -c '{"Args":["getAllDonations"]}'

echo "Waiting for initial query to settle (2s)..."
sleep 2

# Define a set of donations to create using an indexed array (more compatible)
DONATIONS=(
    '{"Args":["createDonation","donation1","donorA","100","charityX","2024-01-01T10:00:00Z"]}'
    # '{"Args":["createDonation","donation2","donorB","250","charityY","2024-01-02T11:00:00Z"]}'
    # '{"Args":["createDonation","donation3","donorC","500","charityZ","2024-01-03T12:00:00Z"]}'
    # '{"Args":["createDonation","donation4","donorA","75","charityX","2024-01-04T13:00:00Z"]}'
    # '{"Args":["createDonation","donation5","donorB","150","charityY","2024-01-05T14:00:00Z"]}'
    # '{"Args":["createDonation","donation6","donorC","300","charityZ","2024-01-06T15:00:00Z"]}'
    # '{"Args":["createDonation","donation7","donorA","120","charityX","2024-01-07T16:00:00Z"]}'
    # '{"Args":["createDonation","donation8","donorB","400","charityY","2024-01-08T17:00:00Z"]}'
    # '{"Args":["createDonation","donation9","donorC","600","charityZ","2024-01-09T18:00:00Z"]}'
)

# Process all donations
for DONATION_JSON in "${DONATIONS[@]}"; do
    # Extract donationId for logging and verification using awk (more compatible than grep -P)
    # This extracts the second argument from the "Args" array in the JSON string
    DONATION_ID=$(echo "$DONATION_JSON" | awk -F'\"' '{print $6}')

    echo "--------------------------------------------------"
    echo "Creating donation '$DONATION_ID'..."
    
    # Capture and display transaction result
    TX_RESULT=$(docker exec cli peer chaincode invoke \
      -o "orderer.${ORDERER_DOMAIN}:7050" --tls --cafile "$ORDERER_CA_PATH_IN_CLI" \
      -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
      -c "$DONATION_JSON" \
      --peerAddresses "peer0-${CHARITY_ORG}.${CHARITY_DOMAIN}:7051" --tlsRootCertFiles "$CHARITY_PEER_TLS_CA_PATH_IN_CLI" \
      --peerAddresses "peer0-${DONOR_ORG}.${DONOR_DOMAIN}:9051" --tlsRootCertFiles "$DONOR_PEER_TLS_CA_PATH_IN_CLI" \
      --waitForEvent)
    
    echo "Transaction result:"
    echo "$TX_RESULT"
    
    # Verify the donation was committed
    verify_donation "$DONATION_ID"
    
    # Small delay between transactions
    sleep 2
done

echo "--------------------------------------------------"
echo "Final ledger state:"
ALL_DONATIONS=$(docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["getAllDonations"]}')
echo "All Donations:\n$ALL_DONATIONS"

echo "All NFTs:"
ALL_NFTS=$(docker exec cli peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CHAINCODE_NAME" \
  -c '{"Args":["getAllNFTs"]}')
echo "All NFTs:\n$ALL_NFTS"

echo "=================================================="
echo "CharityChain network deployment and basic test complete!"
echo "=================================================="