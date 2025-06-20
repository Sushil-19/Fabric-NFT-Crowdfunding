# Hyperledger Fabric Backend

This is a Node.js (TypeScript) backend application that interacts with a Hyperledger Fabric network to manage donations and NFTs.

## Project Structure

```
.
├── src/
│   ├── app.ts            # Main Express application, API routes
│   └── fabricService.ts  # Logic for interacting with Hyperledger Fabric CLI
├── package.json
├── tsconfig.json
└── README.md             # This file
```

## Prerequisites

Before running this backend, ensure you have:

1.  **Node.js (LTS version recommended)** and **npm** installed.
2.  **TypeScript** installed globally or locally (`npm install -g typescript` or `npm install typescript`).
3.  **Your Hyperledger Fabric network setup files** (`deploy-charitychain.sh`, `test.sh`, `organizations`, `chaincode`, etc.) in the **parent directory** relative to where this Node.js project is located. The `fabricService.ts` assumes the `deploy-charitychain.sh` script is at `../../deploy-charitychain.sh` from `src/fabricService.ts`. **Adjust the `fabricProjectPath` in `src/app.ts` if your directory structure is different.**
4.  **Docker Desktop** running.

## Installation

1.  **Navigate into the backend project directory** (e.g., `cd path/to/your/backend`).
2.  **Install dependencies:**
    ```bash
    npm install
    ```

## Running the Application

### Development Mode (with Nodemon)

```bash
npm run dev
```
This will start the server and automatically restart it on code changes.

### Production Mode

1.  **Build the TypeScript code:**
    ```bash
    npm run build
    ```
2.  **Start the server:**
    ```bash
    npm start
    ```

The server will typically run on `http://localhost:3000`.

## API Endpoints

All API endpoints will return JSON responses.

### 1. Deploy Fabric Network

**Initiates the deployment of your Hyperledger Fabric network.** This will execute `deploy-charitychain.sh`. This is a long-running operation.

* **URL:** `/network/deploy`
* **Method:** `POST`
* **Body:** None
* **Example Request (using curl):**
    ```bash
    curl -X POST http://localhost:3000/network/deploy
    ```
* **Example Success Response (202 Accepted):**
    ```json
    {
        "message": "Fabric network deployment initiated. Check server logs for progress."
    }
    ```

### 2. Create New Donation

**Creates a new donation record on the ledger and mints an associated NFT.**

* **URL:** `/donations`
* **Method:** `POST`
* **Body:** JSON object with donation details.
    ```json
    {
        "donationId": "donation_xyz",
        "donorId": "donor_abc",
        "amount": "150",
        "charityId": "charity_mno",
        "timestamp": "2024-06-19T10:30:00Z"
    }
    ```
* **Example Request (using curl):**
    ```bash
    curl -X POST -H "Content-Type: application/json" -d '{
        "donationId": "donationApi1",
        "donorId": "donorE",
        "amount": "200",
        "charityId": "charityZ",
        "timestamp": "2024-06-19T15:00:00Z"
    }' http://localhost:3000/donations
    ```
* **Example Success Response (200 OK):**
    ```json
    {
        "message": "Donation created successfully",
        "data": "{\"donationId\":\"donationApi1\",\"donorId\":\"donorE\",\"amount\":\"200\",\"charityId\":\"charityZ\",\"timestamp\":\"2024-06-19T15:00:00Z\",\"docType\":\"donation\",\"nftId\":\"nft-donationApi1\"}"
    }
    ```

### 3. Get All Donations

**Retrieves all donation records from the ledger.**

* **URL:** `/donations`
* **Method:** `GET`
* **Example Request (using curl):**
    ```bash
    curl http://localhost:3000/donations
    ```
* **Example Success Response (200 OK):**
    ```json
    {
        "message": "Successfully retrieved all donations",
        "data": [
            {
                "donationId": "donation0",
                "donorId": "initialDonor",
                "amount": "50",
                "charityId": "initialCharity",
                "timestamp": "2023-01-01T00:00:00Z",
                "nftId": "nft0",
                "docType": "donation"
            },
            {
                "donationId": "donationApi1",
                "donorId": "donorE",
                "amount": "200",
                "charityId": "charityZ",
                "timestamp": "2024-06-19T15:00:00Z",
                "docType": "donation",
                "nftId": "nft-donationApi1"
            }
        ]
    }
    ```

### 4. Get All NFTs

**Retrieves all NFT metadata records from the ledger.**

* **URL:** `/nfts`
* **Method:** `GET`
* **Example Request (using curl):**
    ```bash
    curl http://localhost:3000/nfts
    ```
* **Example Success Response (200 OK):**
    ```json
    {
        "message": "Successfully retrieved all NFTs",
        "data": [
            {
                "nftId": "nft0",
                "donationId": "donation0",
                "donorId": "initialDonor",
                "amount": "50",
                "charityId": "initialCharity",
                "timestamp": "2023-01-01T00:00:00Z",
                "description": "A unique NFT representing a donation of 50 from initialDonor to initialCharity",
                "image": "[https://example.com/nft_image.png](https://example.com/nft_image.png)"
            },
            {
                "nftId": "nft-donationApi1",
                "donationId": "donationApi1",
                "donorId": "donorE",
                "amount": "200",
                "charityId": "charityZ",
                "timestamp": "2024-06-19T15:00:00Z",
                "description": "A unique NFT representing a donation of 200 from donorE to charityZ",
                "image": "[https://example.com/nft_image.png](https://example.com/nft_image.png)"
            }
        ]
    }
    ```

## Important Notes:

* **Fabric Network State:** This backend assumes your Fabric network is in a ready state (peers, orderer, CAs running). The `/network/deploy` API helps with initial setup.
* **`deploy-charitychain.sh` Location:** The `fabricService.ts` file assumes your `deploy-charitychain.sh` and associated Fabric project folders (`organizations`, `chaincode`, etc.) are in the **parent directory** of this Node.js backend. If your project structure is different, you **must adjust the `fabricProjectPath` variable** in `src/app.ts` accordingly.
    * Example: If your backend is in `/myproject/backend` and Fabric files are in `/myproject/fabric`, `fabricProjectPath` should point to `/myproject/fabric`.
* **Error Handling:** Basic error handling is in place, but for a production application, you would need more robust error logging and user-friendly error messages.
* **Security:** This example does not include any authentication or authorization for the API endpoints. For a real-world application, this is essential.
* **Concurrency:** Repeated calls to `/network/deploy` might cause issues if a deployment is already in progress. Consider adding state management to prevent multiple simultaneous deployments.



curl -X POST http://localhost:4000/network/deploy

curl -X POST -H "Content-Type: application/json" -d '{
    "donationId": "apiDonation1",
    "donorId": "apiDonor1",
    "amount": "123",
    "charityId": "apiCharity1",
    "timestamp": "2024-06-19T10:00:00Z"
}' http://localhost:4000/donations

curl http://localhost:4000/donations

curl http://localhost:4000/nfts