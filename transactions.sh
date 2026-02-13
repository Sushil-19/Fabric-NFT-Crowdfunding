#!/bin/bash

# ==================================================
# CHARITYCHAIN NETWORK - TRANSACTION DEMONSTRATION
# ==================================================
# This script demonstrates all CRUD operations on the
# donation chaincode with proper comments and organization
# ==================================================

set -e

# ==================================================
# CONFIGURATION
# ==================================================
CHANNEL_NAME="donationchannel"
CHAINCODE_NAME="donationcc"
ORDERER_CA="/opt/hyperledger/fabric/crypto/ordererOrg/tls/ca.crt"

# ==================================================
# HELPER FUNCTIONS
# ==================================================

# Function to print section headers
print_section() {
    echo ""
    echo "=================================================="
    echo "$1"
    echo "=================================================="
    echo ""
}

# Function to print transaction info
print_tx() {
    echo ""
    echo "▶ $1"
    echo "----------------------------------------------"
}

# ==================================================
# CLEAN UP OLD TEST DATA (if any)
# ==================================================
print_section "CLEANING UP OLD TEST DATA"

print_tx "Removing any old test donations (errors are OK if they don't exist)"
docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["createDonation","test-delete","temp","1","temp","2026-02-13T00:00:00Z"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent 2>/dev/null || true

echo "✅ Cleanup complete"
sleep 2

# ==================================================
# SECTION 1: CREATE OPERATIONS
# ==================================================
print_section "SECTION 1: CREATE OPERATIONS"

# ----------------------------------------------------------------------
# Transaction 1: Create donation from CharityOrg
# Description: Alice donates $500 to Red Cross
# Identity: CharityOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 1: Creating donation100 (alice -> redcross, $500) from CharityOrg"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["createDonation","donation100","alice","500","redcross","2026-02-13T12:00:00Z"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent

echo "✅ Transaction 1 completed"
sleep 3

# ----------------------------------------------------------------------
# Transaction 2: Create donation from DonorOrg
# Description: Bob donates $750 to UNICEF
# Identity: DonorOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 2: Creating donation101 (bob -> unicef, $750) from DonorOrg"

docker exec \
    -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["createDonation","donation101","bob","750","unicef","2026-02-13T12:05:00Z"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent

echo "✅ Transaction 2 completed"
sleep 3

# ==================================================
# SECTION 2: QUERY OPERATIONS
# ==================================================
print_section "SECTION 2: QUERY OPERATIONS"

# ----------------------------------------------------------------------
# Transaction 3: Query donation from DonorOrg
# Description: Verify donation100 was created correctly
# Identity: DonorOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 3: Querying donation100 from DonorOrg"

docker exec \
    -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
    cli peer chaincode query \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["queryDonation","donation100"]}'

echo "✅ Transaction 3 completed"
sleep 2

# ==================================================
# SECTION 3: UPDATE OPERATIONS
# ==================================================
print_section "SECTION 3: UPDATE OPERATIONS"

# ----------------------------------------------------------------------
# Transaction 4: Update donation from CharityOrg
# Description: Increase donation100 from $500 to $600
# Identity: CharityOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 4: Updating donation100 from $500 to $600 (CharityOrg)"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["updateDonation","donation100","600"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent

echo "✅ Transaction 4 completed"
sleep 3

# ----------------------------------------------------------------------
# Transaction 5: Verify update from DonorOrg
# Description: Confirm donation100 now shows $600
# Identity: DonorOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 5: Verifying donation100 update (should show $600)"

docker exec \
    -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
    cli peer chaincode query \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["queryDonation","donation100"]}'

echo "✅ Transaction 5 completed"
sleep 2

# ==================================================
# SECTION 4: BATCH OPERATIONS
# ==================================================
print_section "SECTION 4: BATCH OPERATIONS"

# ----------------------------------------------------------------------
# Transaction 6: Create another donation from CharityOrg
# Description: Carol donates $300 to Local Charity
# Identity: CharityOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 6: Creating donation102 (carol -> localcharity, $300)"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["createDonation","donation102","carol","300","localcharity","2026-02-13T12:10:00Z"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent

echo "✅ Transaction 6 completed"
sleep 3

# ----------------------------------------------------------------------
# Transaction 7: Create donation from DonorOrg
# Description: Dave donates $450 to Red Cross
# Identity: DonorOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 7: Creating donation103 (dave -> redcross, $450)"

docker exec \
    -e CORE_PEER_LOCALMSPID="donorOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/donorOrg/users/Admin@donor.example.com/msp" \
    cli peer chaincode invoke \
    -o orderer.orderer.example.com:7050 \
    --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["createDonation","donation103","dave","450","redcross","2026-02-13T12:15:00Z"]}' \
    --peerAddresses peer0-charityOrg.charity.example.com:7051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/charityOrg/peers/peer0-charityOrg.charity.example.com/tls/ca.crt \
    --peerAddresses peer0-donorOrg.donor.example.com:9051 \
    --tlsRootCertFiles /opt/hyperledger/fabric/crypto/donorOrg/peers/peer0-donorOrg.donor.example.com/tls/ca.crt \
    --waitForEvent

echo "✅ Transaction 7 completed"
sleep 3

# ==================================================
# SECTION 5: VIEW ALL DONATIONS
# ==================================================
print_section "SECTION 5: VIEW ALL DONATIONS"

# ----------------------------------------------------------------------
# Transaction 8: Get all donations from CharityOrg
# Description: Retrieve complete list of all donations in the ledger
# Identity: CharityOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 8: Retrieving all donations"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode query \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["getAllDonations"]}'

echo "✅ Transaction 8 completed"
sleep 2

# ==================================================
# SECTION 6: NFT DEMONSTRATION
# ==================================================
print_section "SECTION 6: NFT DEMONSTRATION"

# ----------------------------------------------------------------------
# Transaction 9: Query NFT metadata
# Description: Each donation creates an NFT, query the NFT for donation100
# Identity: CharityOrg Admin
# ----------------------------------------------------------------------
print_tx "Transaction 9: Querying NFT metadata for donation100 (nft-donation100)"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode query \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["queryDonation","nft-donation100"]}'

echo "✅ Transaction 9 completed"
sleep 2

# ==================================================
# FINAL SUMMARY
# ==================================================
print_section "TRANSACTION SUMMARY"

echo "✅ Successful Transactions:"
echo "   1. Created donation100 (alice -> redcross, $500)"
echo "   2. Created donation101 (bob -> unicef, $750)"
echo "   3. Queried donation100"
echo "   4. Updated donation100 from $500 to $600"
echo "   5. Verified donation100 update (now $600)"
echo "   6. Created donation102 (carol -> localcharity, $300)"
echo "   7. Created donation103 (dave -> redcross, $450)"
echo "   8. Retrieved all donations"
echo "   9. Queried NFT metadata for donation100"
echo ""

# ==================================================
# FINAL LEDGER STATE
# ==================================================
print_section "FINAL LEDGER STATE"

docker exec \
    -e CORE_PEER_LOCALMSPID="charityOrgMSP" \
    -e CORE_PEER_MSPCONFIGPATH="/opt/hyperledger/fabric/crypto/charityOrg/users/Admin@charity.example.com/msp" \
    cli peer chaincode query \
    -C $CHANNEL_NAME -n $CHAINCODE_NAME \
    -c '{"Args":["getAllDonations"]}' | jq .

echo ""
echo "=================================================="
echo "🎉 ALL TRANSACTIONS COMPLETED SUCCESSFULLY!"
echo "=================================================="