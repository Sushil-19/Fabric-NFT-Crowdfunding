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
    private readonly CHARITY_DOMAIN = "charity.example.com"; // Added this
    private readonly DONOR_ORG = "donorOrg";
    private readonly DONOR_DOMAIN = "donor.example.com";     // Added this

    // Define paths to orderer and peer TLS CA certs inside CLI for convenience
    private readonly ORDERER_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/ordererOrg/orderers/orderer.${this.ORDERER_DOMAIN}/tls/ca.crt`;
    private readonly CHARITY_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.CHARITY_ORG}/peers/peer0-${this.CHARITY_ORG}.${this.CHARITY_DOMAIN}/tls/ca.crt`;
    private readonly DONOR_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.DONOR_ORG}/peers/peer0-${this.DONOR_ORG}.${this.DONOR_DOMAIN}/tls/ca.crt`;

    constructor(fabricProjectPath: string) {
        this.fabricProjectPath = fabricProjectPath;
    }

    /**
     * Executes a shell command with error handling.
     * @param command The command to execute.
     * @param options The options for child_process.exec.
     * @returns The stdout of the command.
     * @throws Error if the command fails.
     */
    private async executeCommand(command: string, options?: { cwd?: string, env?: NodeJS.ProcessEnv }): Promise<string> {
        console.log(`Executing command: ${command}`);
        try {
            const { stdout, stderr } = await execPromise(command, options);
            const stdoutString = stdout.toString(); // Convert to string
            const stderrString = stderr.toString(); // Convert to string

            if (stderrString.trim()) { // Check if stderr has content after trimming
                console.warn(`Command stderr: ${stderrString.trim()}`);
            }
            return stdoutString.trim();
        } catch (error: any) {
            console.error(`Command failed: ${command}`);
            console.error(`Error stdout: ${error.stdout ? error.stdout.toString() : 'N/A'}`);
            console.error(`Error stderr: ${error.stderr ? error.stderr.toString() : 'N/A'}`);
            throw new Error(`Command execution failed: ${error.stderr ? error.stderr.toString() : error.message}`);
        }
    }

    /**
     * Deploys the Hyperledger Fabric network by running deploy-charitychain.sh.
     * This is an asynchronous operation that logs its output.
     */
    public deployNetwork(): void {
        const scriptPath = path.join(this.fabricProjectPath, 'deploy-charitychain.sh');
        console.log(`Starting network deployment script: ${scriptPath}`);

        // Spawn to handle long-running process and stream output
        const deployProcess = spawn('bash', [scriptPath], {
            cwd: this.fabricProjectPath,
            stdio: 'pipe' // Pipe stdout and stderr
        });

        deployProcess.stdout.on('data', (data) => {
            process.stdout.write(`DEPLOY SCRIPT (stdout): ${data.toString()}`);
        });

        deployProcess.stderr.on('data', (data) => {
            process.stderr.write(`DEPLOY SCRIPT (stderr): ${data.toString()}`);
        });

        deployProcess.on('close', (code) => {
            if (code === 0) {
                console.log('Fabric network deployment script finished successfully.');
            } else {
                console.error(`Fabric network deployment script exited with code ${code}`);
            }
        });

        deployProcess.on('error', (err) => {
            console.error(`Failed to start deployment script process: ${err.message}`);
        });
    }

    /**
     * Executes a chaincode invoke operation.
     * @param functionName The chaincode function to invoke.
     * @param args Arguments for the chaincode function.
     * @returns The result payload from the chaincode.
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

        try {
            const { stdout, stderr } = await execPromise(command, { cwd: this.fabricProjectPath });
            const stderrString = stderr.toString(); // Convert to string
            const stdoutString = stdout.toString(); // Convert to string
            
            // The 'invoke' command often logs the payload to stderr, not stdout.
            if (stderrString.includes('payload:')) {
                const payloadMatch = stderrString.match(/payload:"([^"]*)"/);
                if (payloadMatch && payloadMatch[1]) {
                    // Fabric often escapes inner quotes in the payload. Unescape it.
                    const unescapedPayload = payloadMatch[1].replace(/\\"/g, '"');
                    return unescapedPayload;
                }
            }
            // Fallback: if payload not found in stderr, return stdout or a default message
            return stdoutString.trim() || "Chaincode invoke completed without explicit payload in stdout/stderr.";

        } catch (error: any) {
            // Error.stderr will contain the actual Fabric CLI error message
            throw new Error(`Chaincode invoke failed: ${error.stderr ? error.stderr.toString() : error.message}`);
        }
    }

    /**
     * Executes a chaincode query operation.
     * @param functionName The chaincode function to query.
     * @param args Arguments for the chaincode function.
     * @returns The result from the chaincode query.
     */
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
                return stdout; // Return raw string if not valid JSON
            }
        } catch (error: any) {
            throw new Error(`Chaincode query failed: ${error.message}`);
        }
    }

    // --- Specific Chaincode API Methods ---

    /**
     * Creates a new donation and associated NFT.
     */
    public async createDonation(donationId: string, donorId: string, amount: string, charityId: string, timestamp: string): Promise<string> {
        // Ensure timestamp is properly formatted for the chaincode
        // Example: "2024-01-01T10:00:00Z"
        return this.invokeChaincode('createDonation', [donationId, donorId, amount, charityId, timestamp]);
    }

    /**
     * Retrieves all donation records.
     */
    public async getAllDonations(): Promise<any[]> {
        const result = await this.queryChaincode('getAllDonations', []);
        return result;
    }

    /**
     * Retrieves all NFT metadata.
     */
    public async getAllNFTs(): Promise<any[]> {
        const result = await this.queryChaincode('getAllNFTs', []);
        return result;
    }
}
