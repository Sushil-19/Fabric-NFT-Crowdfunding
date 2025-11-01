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
            console.info(`Donation ${donation.donationId} initialized`);
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
            nftId: `nft-${donationId}` 
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
            description: `A unique NFT representing a donation of ${amount} from ${donorId} to ${charityId}`,
            image: "https://example.com/nft_image.png" 
        };
        await ctx.stub.putState(donation.nftId, Buffer.from(JSON.stringify(nftMetadata)));

        console.info(`Donation ${donationId} created with NFT ${donation.nftId}`);
        return JSON.stringify(donation);
    }

    async queryDonation(ctx, donationId) {
        const donationAsBytes = await ctx.stub.getState(donationId);
        if (!donationAsBytes || donationAsBytes.length === 0) {
            throw new Error(`Donation ${donationId} does not exist`);
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
