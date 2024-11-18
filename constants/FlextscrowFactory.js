const CONTRACT_ADDRESS = "0x9B84831d24fb998a1231E63961ECe5888E9f503F";
const ABI = [
    {
        "type": "constructor",
        "inputs": [
            { "name": "_arbitrator", "type": "address", "internalType": "address" },
            { "name": "_erc20Token", "type": "address", "internalType": "address" },
            { "name": "_flatFee", "type": "uint256", "internalType": "uint256" },
            { "name": "_bps", "type": "uint256", "internalType": "uint256" }
        ],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "allInvoiceIds",
        "inputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
        "outputs": [{ "name": "", "type": "string", "internalType": "string" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "arbitrator",
        "inputs": [],
        "outputs": [{ "name": "", "type": "address", "internalType": "address" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "basepoints",
        "inputs": [],
        "outputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "createEscrow",
        "inputs": [
            { "name": "invoiceId", "type": "string", "internalType": "string" },
            { "name": "buyer", "type": "address", "internalType": "address" },
            { "name": "seller", "type": "address", "internalType": "address" },
            {
                "name": "completionDuration",
                "type": "uint256",
                "internalType": "uint256"
            },
            {
                "name": "releaseTimeout",
                "type": "uint256",
                "internalType": "uint256"
            }
        ],
        "outputs": [{ "name": "", "type": "address", "internalType": "address" }],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "erc20Token",
        "inputs": [],
        "outputs": [{ "name": "", "type": "address", "internalType": "address" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "escrows",
        "inputs": [{ "name": "", "type": "string", "internalType": "string" }],
        "outputs": [
            {
                "name": "escrowAddress",
                "type": "address",
                "internalType": "address"
            },
            { "name": "buyer", "type": "address", "internalType": "address" },
            { "name": "seller", "type": "address", "internalType": "address" },
            { "name": "createdAt", "type": "uint256", "internalType": "uint256" }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "flatFee",
        "inputs": [],
        "outputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getEscrowDetails",
        "inputs": [
            { "name": "invoiceId", "type": "string", "internalType": "string" }
        ],
        "outputs": [
            {
                "name": "escrowAddress",
                "type": "address",
                "internalType": "address"
            },
            { "name": "buyer", "type": "address", "internalType": "address" },
            { "name": "seller", "type": "address", "internalType": "address" },
            { "name": "createdAt", "type": "uint256", "internalType": "uint256" }
        ],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "getTotalEscrows",
        "inputs": [],
        "outputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "owner",
        "inputs": [],
        "outputs": [{ "name": "", "type": "address", "internalType": "address" }],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "renounceOwnership",
        "inputs": [],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "transferOwnership",
        "inputs": [
            { "name": "newOwner", "type": "address", "internalType": "address" }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "updateFees",
        "inputs": [
            { "name": "_flatFee", "type": "uint256", "internalType": "uint256" },
            { "name": "_bps", "type": "uint256", "internalType": "uint256" }
        ],
        "outputs": [],
        "stateMutability": "nonpayable"
    },
    {
        "type": "event",
        "name": "EscrowCreated",
        "inputs": [
            {
                "name": "invoiceId",
                "type": "string",
                "indexed": true,
                "internalType": "string"
            },
            {
                "name": "escrow",
                "type": "address",
                "indexed": true,
                "internalType": "address"
            },
            {
                "name": "buyer",
                "type": "address",
                "indexed": true,
                "internalType": "address"
            },
            {
                "name": "seller",
                "type": "address",
                "indexed": false,
                "internalType": "address"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "FeeUpdated",
        "inputs": [
            {
                "name": "flatFee",
                "type": "uint256",
                "indexed": false,
                "internalType": "uint256"
            },
            {
                "name": "basepoints",
                "type": "uint256",
                "indexed": false,
                "internalType": "uint256"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "OwnershipTransferred",
        "inputs": [
            {
                "name": "previousOwner",
                "type": "address",
                "indexed": true,
                "internalType": "address"
            },
            {
                "name": "newOwner",
                "type": "address",
                "indexed": true,
                "internalType": "address"
            }
        ],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "TimeOutUpdated",
        "inputs": [
            {
                "name": "releaseTimeout",
                "type": "uint256",
                "indexed": false,
                "internalType": "uint256"
            }
        ],
        "anonymous": false
    },
    { "type": "error", "name": "EscrowAlreadyExists", "inputs": [] },
    { "type": "error", "name": "InvalidArbitratorAddress", "inputs": [] },
    { "type": "error", "name": "InvalidERC20TokenAddress", "inputs": [] },
    { "type": "error", "name": "InvalidInvoiceId", "inputs": [] },
    {
        "type": "error",
        "name": "OwnableInvalidOwner",
        "inputs": [
            { "name": "owner", "type": "address", "internalType": "address" }
        ]
    },
    {
        "type": "error",
        "name": "OwnableUnauthorizedAccount",
        "inputs": [
            { "name": "account", "type": "address", "internalType": "address" }
        ]
    }
]
