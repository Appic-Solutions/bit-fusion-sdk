import { expect } from 'chai';
import { ethers } from 'ethers';
import chai from 'chai';
import chaiAsPromised from 'chai-as-promised';
chai.use(chaiAsPromised);

const BRIDGE_ABI = [
    {
        "inputs": [],
        "name": "NATIVE_TOKEN_ADDRESS",
        "outputs": [{ "internalType": "address", "name": "", "type": "address" }],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "uint256", "name": "amount", "type": "uint256" },
            { "internalType": "address", "name": "fromERC20", "type": "address" },
            { "internalType": "bytes32", "name": "toTokenID", "type": "bytes32" },
            { "internalType": "bytes", "name": "recipientID", "type": "bytes" },
            { "internalType": "bytes32", "name": "memo", "type": "bytes32" }
        ],
        "name": "burn",
        "outputs": [{ "internalType": "uint32", "name": "", "type": "uint32" }],
        "stateMutability": "payable",
        "type": "function"
    }
];

describe("BTF Bridge Native Token Tests", () => {
    let provider: ethers.JsonRpcProvider;
    let bridgeContract: ethers.Contract;
    let signer: ethers.Wallet;

    const BRIDGE_ADDRESS = "0x0150B54605423F85d076Ea483De87e488fC266AE";

    before(async () => {
        console.log("Setting up test environment...");
        provider = new ethers.JsonRpcProvider('https://holesky.infura.io/v3/895d773d17f043008769af24d76f0ac1');
        const contractBalance = await provider.getBalance(BRIDGE_ADDRESS);
        console.log("Bridge Contract ETH Balance:", ethers.formatEther(contractBalance));
        
        const privateKey = '0x388011f48124700b5c553b4b1c4b10b31e9c04fecb7b3b85a4231b8ede8d126e';
        signer = new ethers.Wallet(privateKey, provider);
        console.log("Signer address:", await signer.getAddress());

        bridgeContract = new ethers.Contract(
            BRIDGE_ADDRESS,
            BRIDGE_ABI,
            signer
        );

        // Verify contract is deployed
        const code = await provider.getCode(BRIDGE_ADDRESS);
        console.log("Contract code length:", code.length);
        if (code === '0x') throw new Error('Contract not found at address');
    });

    describe("Native Token Operations", () => {
        it("should burn native ETH tokens successfully", async function() {
            this.timeout(60000); // Increased timeout to 60s
        
            const amount = ethers.parseEther("0.01");
            const toTokenId = ethers.zeroPadBytes(ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
            const recipientId = ethers.toUtf8Bytes(await signer.getAddress());
            const memo = ethers.ZeroHash;
        
            console.log("Preparing burn transaction...");
            console.log("Amount:", ethers.formatEther(amount), "ETH");
            console.log("Recipient:", ethers.hexlify(recipientId));
        
            try {
                // Check initial balances
                const initialBalance = await provider.getBalance(signer.address);
                console.log("Initial balance:", ethers.formatEther(initialBalance));
        
                // Send transaction (Removed estimateGas since it's redundant)
                const tx = await bridgeContract.burn(
                    amount,
                    ethers.ZeroAddress,
                    toTokenId,
                    recipientId,
                    memo,
                    { value: amount }
                );
        
                console.log("Transaction sent:", tx.hash);
                const receipt = await tx.wait();
                console.log("Transaction confirmed in block:", receipt.blockNumber);
        
                const finalBalance = await provider.getBalance(signer.address);
                console.log("Final balance:", ethers.formatEther(finalBalance));
        
                expect(initialBalance - finalBalance > amount).to.be.true;
            } catch (error) {
                console.error("Error burning native tokens:", error);
                throw error;
            }
        });
        

        it("should fail if incorrect ETH amount is sent", async function () {
            this.timeout(30000);
        
            const amount = ethers.parseEther("0.01");
            const toTokenId = ethers.zeroPadBytes(ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
            const recipientId = ethers.toUtf8Bytes(await signer.getAddress());
            const memo = ethers.ZeroHash;
        
            console.log("Testing burn failure due to incorrect ETH amount...");
        
            await expect(
                bridgeContract.burn(
                    amount, // Expecting 0.01 ETH burn
                    ethers.ZeroAddress,
                    toTokenId,
                    recipientId,
                    memo,
                    { value: ethers.parseEther("0.015") } // Sending 0.015 ETH instead
                )
            ).to.be.rejectedWith(Error);
        });
        
        
        
        
        it("should fail if user has insufficient ETH", async function () {
            this.timeout(30000);
        
            const amount = ethers.parseEther("1000"); // Large amount to force failure
            const toTokenId = ethers.zeroPadBytes(ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
            const recipientId = ethers.toUtf8Bytes(await signer.getAddress());
            const memo = ethers.ZeroHash;
        
            console.log("Testing burn failure due to insufficient ETH...");
        
            await expect(
                bridgeContract.burn(
                    amount,
                    ethers.ZeroAddress,
                    toTokenId,
                    recipientId,
                    memo,
                    { value: amount }
                )
            ).to.be.rejectedWith(Error);
        });
        
        
        

    });
});


