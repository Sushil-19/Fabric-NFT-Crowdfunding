// src/app.ts
import express from 'express';
import bodyParser from 'body-parser';
import { FabricService } from './fabricService';
import path from 'path';

const app = express();
const port = 4000;

// Middleware
app.use(bodyParser.json());

// Initialize FabricService with the base path where your Hyperledger Fabric project resides
// Assuming your deploy-charitychain.sh is at the root of your Fabric project
// and this Node.js backend is at the same level or configured correctly.
const fabricProjectPath = path.resolve(__dirname, '../../'); // Adjust this path as needed
const fabricService = new FabricService(fabricProjectPath);

// Routes

/**
 * @api {post} /network/deploy Deploy Fabric Network
 * @apiName DeployNetwork
 * @apiGroup Network
 * @apiDescription Executes the deploy-charitychain.sh script to set up the Hyperledger Fabric network.
 * This is a long-running operation and should only be triggered when setting up or resetting the network.
 * @apiSuccess {String} message Status message indicating deployment initiation.
 * @apiError {Object} error Error details if the deployment fails to start.
 */
app.post('/network/deploy', async (req, res) => {
    try {
        console.log('API: Initiating Fabric network deployment...');
        // Execute the deploy script in the background or with streaming output if needed
        fabricService.deployNetwork();
        res.status(202).send({ message: 'Fabric network deployment initiated. Check server logs for progress.' });
    } catch (error: any) {
        console.error(`API: Error initiating deployment: ${error.message}`);
        res.status(500).send({ error: `Failed to initiate network deployment: ${error.message}` });
    }
});

/**
 * @api {post} /donations Create New Donation
 * @apiName CreateDonation
 * @apiGroup Donations
 * @apiDescription Creates a new donation record on the Hyperledger Fabric ledger and mints an associated NFT.
 * @apiBody {String} donationId Unique ID for the donation.
 * @apiBody {String} donorId ID of the donor.
 * @apiBody {String} amount Amount of the donation (as a string).
 * @apiBody {String} charityId ID of the charity receiving the donation.
 * @apiBody {String} timestamp ISO 8601 formatted timestamp (e.g., "2024-01-01T10:00:00Z").
 * @apiSuccess {String} message Success message.
 * @apiSuccess {Object} data JSON string of the created donation object.
 * @apiError {Object} error Error details if the transaction fails.
 */
app.post('/donations', async (req, res) => {
    const { donationId, donorId, amount, charityId, timestamp } = req.body;

    if (!donationId || !donorId || !amount || !charityId || !timestamp) {
        return res.status(400).send({ error: 'Missing required fields for donation.' });
    }

    try {
        console.log(`API: Creating donation: ${donationId}`);
        const result = await fabricService.createDonation(donationId, donorId, amount, charityId, timestamp);
        let responseData;
        try {
            // Attempt to parse the string result into a JSON object.
            responseData = JSON.parse(result);
        } catch (e) {
            // If parsing fails, it might be a simple string message (e.g., "OK").
            // In that case, we'll just send the raw string.
            console.warn('The chaincode response was not a valid JSON string. Returning raw response.');
            responseData = result;
        }
        res.status(200).send({ message: 'Donation created successfully', responseData });
    } catch (error: any) {
        console.error(`API: Error creating donation: ${error.message}`);
        res.status(500).send({ error: `Failed to create donation: ${error.message}` });
    }
});

/**
 * @api {get} /donations Get All Donations
 * @apiName GetAllDonations
 * @apiGroup Donations
 * @apiDescription Retrieves all donation records from the Hyperledger Fabric ledger.
 * @apiSuccess {String} message Success message.
 * @apiSuccess {Object[]} data Array of donation objects.
 * @apiError {Object} error Error details if the query fails.
 */
app.get('/donations', async (req, res) => {
    try {
        console.log('API: Fetching all donations...');
        const result = await fabricService.getAllDonations();
        res.status(200).send({ message: 'Successfully retrieved all donations', data: result });
    } catch (error: any) {
        console.error(`API: Error fetching all donations: ${error.message}`);
        res.status(500).send({ error: `Failed to retrieve donations: ${error.message}` });
    }
});

/**
 * @api {get} /nfts Get All NFTs
 * @apiName GetAllNFTs
 * @apiGroup NFTs
 * @apiDescription Retrieves all NFT metadata records from the Hyperledger Fabric ledger.
 * @apiSuccess {String} message Success message.
 * @apiSuccess {Object[]} data Array of NFT metadata objects.
 * @apiError {Object} error Error details if the query fails.
 */
app.get('/nfts', async (req, res) => {
    try {
        console.log('API: Fetching all NFTs...');
        const result = await fabricService.getAllNFTs();
        res.status(200).send({ message: 'Successfully retrieved all NFTs', data: result });
    } catch (error: any) {
        console.error(`API: Error fetching all NFTs: ${error.message}`);
        res.status(500).send({ error: `Failed to retrieve NFTs: ${error.message}` });
    }
});


// Start the server
app.listen(port, () => {
    console.log(`Backend server listening at http://localhost:${port}`);
    console.log(`API documentation (if generated) would be at http://localhost:${port}/api-docs`);
});
