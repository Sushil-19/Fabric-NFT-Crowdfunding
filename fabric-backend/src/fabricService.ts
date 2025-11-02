// src/fabricService.ts
import { exec, spawn } from 'child_process';
import path from 'path';
import { promisify } from 'util';

const execPromise = promisify(exec);

export class FabricService {
    private fabricProjectPath: string;
    private readonly CHAINCODE_NAME = "donationcc";
    private readonly CHANNEL_NAME = "donationchannel";
    private readonly ORDERER_DOMAIN = "orderer.example.com";
    private readonly CHARITY_ORG = "charityOrg";
    private readonly CHARITY_DOMAIN = "charity.example.com";
    private readonly DONOR_ORG = "donorOrg";
    private readonly DONOR_DOMAIN = "donor.example.com";

    // Define paths to orderer and peer TLS CA certs inside CLI for convenience
    private readonly ORDERER_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/ordererOrg/orderers/orderer.${this.ORDERER_DOMAIN}/tls/ca.crt`;
    private readonly CHARITY_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.CHARITY_ORG}/peers/peer0-${this.CHARITY_ORG}.${this.CHARITY_DOMAIN}/tls/ca.crt`;
    private readonly DONOR_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.DONOR_ORG}/peers/peer0-${this.DONOR_ORG}.${this.DONOR_DOMAIN}/tls/ca.crt`;

    constructor(fabricProjectPath: string) {
        this.fabricProjectPath = fabricProjectPath;
    }

    private async executeCommand(command: string, options?: { cwd?: string, env?: NodeJS.ProcessEnv }): Promise<string> {
        // This helper is now primarily for query, which reliably uses stdout
        try {
            const { stdout, stderr } = await execPromise(command, options);
            if (stderr) {
                console.warn(`Command stderr: ${stderr}`);
            }
            return stdout.toString().trim();
        } catch (error: any) {
            const errorMessage = error.stderr?.toString() || error.stdout?.toString() || error.message;
            console.error(`Command execution failed: ${errorMessage}`);
            throw new Error(`Command execution failed: ${errorMessage}`);
        }
    }

    public deployNetwork(): void {
        const scriptPath = path.join(this.fabricProjectPath, 'deploy-charitychain.sh');
        console.log(`Starting network deployment script: ${scriptPath}`);
        const deployProcess = spawn('bash', [scriptPath], { cwd: this.fabricProjectPath, stdio: 'pipe' });
        deployProcess.stdout.on('data', (data) => process.stdout.write(`DEPLOY SCRIPT (stdout): ${data}`));
        deployProcess.stderr.on('data', (data) => process.stderr.write(`DEPLOY SCRIPT (stderr): ${data}`));
        deployProcess.on('close', (code) => {
            if (code === 0) console.log('Fabric network deployment script finished successfully.');
            else console.error(`Fabric network deployment script exited with code ${code}`);
        });
        deployProcess.on('error', (err) => console.error(`Failed to start deployment script process: ${err.message}`));
    }

    /**
     * Executes a chaincode invoke operation. This version no longer assumes the command will
     * fail and proactively parses the output for the payload.
     */
    public async invokeChaincode(functionName: string, args: string[]): Promise<string> {
        const argsJson = JSON.stringify({ Args: [functionName, ...args] });
        const command = `docker exec cli peer chaincode invoke \
            -o "orderer.${this.ORDERER_DOMAIN}:7050" --tls --cafile "${this.ORDERER_CA_PATH_IN_CLI}" \
            -C "${this.CHANNEL_NAME}" -n "${this.CHAINCODE_NAME}" \
            -c '${argsJson}' \
            --peerAddresses "peer0-${this.CHARITY_ORG}.${this.CHARITY_DOMAIN}:7051" --tlsRootCertFiles "${this.CHARITY_PEER_TLS_CA_PATH_IN_CLI}" \
            --peerAddresses "peer0-${this.DONOR_ORG}.${this.DONOR_DOMAIN}:9051" --tlsRootCertFiles "${this.DONOR_PEER_TLS_CA_PATH_IN_CLI}" \
            --waitForEvent`;

        console.log(`Executing invoke command: ${command}`);
        try {
            // Execute the command and capture both stdout and stderr from the result
            const { stdout, stderr } = await execPromise(command, { cwd: this.fabricProjectPath });
            
            // The payload can be in stderr even on a successful exit. Combine both streams.
            const output = stdout.toString() + stderr.toString();
            console.log("Invoke command full output:", output);

            const payloadMarker = 'payload:';
            const payloadIndex = output.indexOf(payloadMarker);

            if (payloadIndex !== -1) {
                // Extract the substring that starts after 'payload:'
                let payload = output.substring(payloadIndex + payloadMarker.length);
                
                // Find the first '{' and last '}' to reliably extract the JSON object
                const firstBrace = payload.indexOf('{');
                const lastBrace = payload.lastIndexOf('}');

                if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
                    const jsonPayload = payload.substring(firstBrace, lastBrace + 1);
                    console.log(`Successfully extracted payload: ${jsonPayload}`);
                    return jsonPayload;
                }
            }

            // If the command succeeded but we couldn't find a payload, we log it.
            console.warn("Invoke completed, but no valid JSON payload was found in the output.");
            // Return a structured error message
            return JSON.stringify({ error: "Invoke completed, but no valid JSON payload was found." });

        } catch (error: any) {
            // This block will now only catch genuine command execution failures.
            // However, we still check the output for a payload, as some errors might contain it.
             const output = error.stderr?.toString() || error.stdout?.toString() || "";
             if (output.includes('payload:')) {
                // If there's an error but we still got a payload, let's try to return it
                 const payloadMarker = 'payload:';
                 const payloadIndex = output.indexOf(payloadMarker);
                 let payload = output.substring(payloadIndex + payloadMarker.length);
                 const firstBrace = payload.indexOf('{');
                 const lastBrace = payload.lastIndexOf('}');
                 if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
                     const jsonPayload = payload.substring(firstBrace, lastBrace + 1);
                     console.log(`Successfully extracted payload from error output: ${jsonPayload}`);
                     return jsonPayload;
                 }
             }

            const errorMessage = error.stderr?.toString() || error.stdout?.toString() || error.message;
            console.error(`Chaincode invoke failed with an error: ${errorMessage}`);
            throw new Error(`Chaincode invoke failed: ${errorMessage}`);
        }
    }

    public async queryChaincode(functionName: string, args: string[]): Promise<any> {
        const argsJson = JSON.stringify({ Args: [functionName, ...args] });
        const command = `docker exec cli peer chaincode query \
            -C "${this.CHANNEL_NAME}" -n "${this.CHAINCODE_NAME}" \
            -c '${argsJson}'`;

        try {
            const stdout = await this.executeCommand(command, { cwd: this.fabricProjectPath });
            try {
                return JSON.parse(stdout);
            } catch (parseError) {
                console.warn(`Could not parse query result as JSON, returning raw string. Error: ${parseError}`);
                return stdout;
            }
        } catch (error: any) {
            throw new Error(`Chaincode query failed: ${error.message}`);
        }
    }

    public async createDonation(donationId: string, donorId: string, amount: string, charityId: string, timestamp: string): Promise<string> {
        return this.invokeChaincode('createDonation', [donationId, donorId, amount, charityId, timestamp]);
    }

    public async getAllDonations(): Promise<any[]> {
        return this.queryChaincode('getAllDonations', []);
    }

    public async getAllNFTs(): Promise<any[]> {
        try {
            // Try different possible chaincode function names
            let result;
            try {
                result = await this.queryChaincode('getAllNFTs', []);
            } catch (error) {
                console.log('getAllNFTs failed, trying GetAllNFTs...');
                result = await this.queryChaincode('GetAllNFTs', []);
            }
            
            console.log('NFT data from chaincode:', result);
            
            if (!result || (Array.isArray(result) && result.length === 0)) {
                console.log('No NFT data found');
                return [];
            }
            
            let nfts = Array.isArray(result) ? result : [result];
            
            console.log(`Processing ${nfts.length} NFTs`);
            
            // Add hash directly to each NFT
            return nfts.map((nft, index) => {
                if (!nft || typeof nft !== 'object') return null;
                
                // Create simple hash
                const nftId = nft.nftId || nft.NFTID || `nft-${index + 1}`;
                const charityId = nft.charityId || nft.CharityID || 'unknown';
                const timestamp = nft.timestamp || nft.Timestamp || new Date().toISOString();
                
                const data = nftId + charityId + timestamp;
                let hash = 0;
                for (let i = 0; i < data.length; i++) {
                    hash = ((hash << 5) - hash) + data.charCodeAt(i);
                    hash = hash & hash;
                }
                const uniqueHash = 'h' + Math.abs(hash).toString(16).substring(0, 8);
                
                return {
                    nftId: nftId,
                    transactionId: nft.transactionId || nft.TransactionID || 'N/A',
                    donationId: nft.donationId || nft.DonationID || 'N/A',
                    donorId: nft.donorId || nft.DonorID || 'N/A',
                    amount: nft.amount || nft.Amount || 'N/A',
                    charityId: charityId,
                    timestamp: timestamp,
                    uniqueHash: uniqueHash
                };
            }).filter(nft => nft !== null);
            
        } catch (error) {
            console.error('Error getting NFTs:', error);
            return [];
        }
    }
    
    
}