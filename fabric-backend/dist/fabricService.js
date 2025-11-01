"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FabricService = void 0;
// src/fabricService.ts
const child_process_1 = require("child_process");
const path_1 = __importDefault(require("path"));
const util_1 = require("util");
const execPromise = (0, util_1.promisify)(child_process_1.exec);
class FabricService {
    constructor(fabricProjectPath) {
        this.CHAINCODE_NAME = "donationcc";
        this.CHANNEL_NAME = "donationchannel";
        this.ORDERER_DOMAIN = "orderer.example.com";
        this.CHARITY_ORG = "charityOrg";
        this.CHARITY_DOMAIN = "charity.example.com";
        this.DONOR_ORG = "donorOrg";
        this.DONOR_DOMAIN = "donor.example.com";
        // Define paths to orderer and peer TLS CA certs inside CLI for convenience
        this.ORDERER_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/ordererOrg/orderers/orderer.${this.ORDERER_DOMAIN}/tls/ca.crt`;
        this.CHARITY_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.CHARITY_ORG}/peers/peer0-${this.CHARITY_ORG}.${this.CHARITY_DOMAIN}/tls/ca.crt`;
        this.DONOR_PEER_TLS_CA_PATH_IN_CLI = `/opt/hyperledger/fabric/crypto/${this.DONOR_ORG}/peers/peer0-${this.DONOR_ORG}.${this.DONOR_DOMAIN}/tls/ca.crt`;
        this.fabricProjectPath = fabricProjectPath;
    }
    async executeCommand(command, options) {
        var _a, _b;
        // This helper is now primarily for query, which reliably uses stdout
        try {
            const { stdout, stderr } = await execPromise(command, options);
            if (stderr) {
                console.warn(`Command stderr: ${stderr}`);
            }
            return stdout.toString().trim();
        }
        catch (error) {
            const errorMessage = ((_a = error.stderr) === null || _a === void 0 ? void 0 : _a.toString()) || ((_b = error.stdout) === null || _b === void 0 ? void 0 : _b.toString()) || error.message;
            console.error(`Command execution failed: ${errorMessage}`);
            throw new Error(`Command execution failed: ${errorMessage}`);
        }
    }
    deployNetwork() {
        const scriptPath = path_1.default.join(this.fabricProjectPath, 'deploy-charitychain.sh');
        console.log(`Starting network deployment script: ${scriptPath}`);
        const deployProcess = (0, child_process_1.spawn)('bash', [scriptPath], { cwd: this.fabricProjectPath, stdio: 'pipe' });
        deployProcess.stdout.on('data', (data) => process.stdout.write(`DEPLOY SCRIPT (stdout): ${data}`));
        deployProcess.stderr.on('data', (data) => process.stderr.write(`DEPLOY SCRIPT (stderr): ${data}`));
        deployProcess.on('close', (code) => {
            if (code === 0)
                console.log('Fabric network deployment script finished successfully.');
            else
                console.error(`Fabric network deployment script exited with code ${code}`);
        });
        deployProcess.on('error', (err) => console.error(`Failed to start deployment script process: ${err.message}`));
    }
    /**
     * Executes a chaincode invoke operation. This version no longer assumes the command will
     * fail and proactively parses the output for the payload.
     */
    async invokeChaincode(functionName, args) {
        var _a, _b, _c, _d;
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
        }
        catch (error) {
            // This block will now only catch genuine command execution failures.
            // However, we still check the output for a payload, as some errors might contain it.
            const output = ((_a = error.stderr) === null || _a === void 0 ? void 0 : _a.toString()) || ((_b = error.stdout) === null || _b === void 0 ? void 0 : _b.toString()) || "";
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
            const errorMessage = ((_c = error.stderr) === null || _c === void 0 ? void 0 : _c.toString()) || ((_d = error.stdout) === null || _d === void 0 ? void 0 : _d.toString()) || error.message;
            console.error(`Chaincode invoke failed with an error: ${errorMessage}`);
            throw new Error(`Chaincode invoke failed: ${errorMessage}`);
        }
    }
    async queryChaincode(functionName, args) {
        const argsJson = JSON.stringify({ Args: [functionName, ...args] });
        const command = `docker exec cli peer chaincode query \
            -C "${this.CHANNEL_NAME}" -n "${this.CHAINCODE_NAME}" \
            -c '${argsJson}'`;
        try {
            const stdout = await this.executeCommand(command, { cwd: this.fabricProjectPath });
            try {
                return JSON.parse(stdout);
            }
            catch (parseError) {
                console.warn(`Could not parse query result as JSON, returning raw string. Error: ${parseError}`);
                return stdout;
            }
        }
        catch (error) {
            throw new Error(`Chaincode query failed: ${error.message}`);
        }
    }
    async createDonation(donationId, donorId, amount, charityId, timestamp) {
        return this.invokeChaincode('createDonation', [donationId, donorId, amount, charityId, timestamp]);
    }
    async getAllDonations() {
        return this.queryChaincode('getAllDonations', []);
    }
    async getAllNFTs() {
        return this.queryChaincode('getAllNFTs', []);
    }
}
exports.FabricService = FabricService;
