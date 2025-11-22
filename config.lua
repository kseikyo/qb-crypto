Config = {}

Config.Crypto = {
    Lower = 500,
    Upper = 5000,
    History = {
        ["qbit"] = {}
    },

    Worth = {
        ["qbit"] = 1000
    },

    Labels = {
        ["qbit"] = "Qbit"
    },

    Exchange = {
        coords = vector3(1276.21, -1709.88, 54.57),
        RebootInfo = {
            state = false,
            percentage = 0
        },
    },

    -- For auto updating the value of qbit
    Coin = 'qbit',
    RefreshTimer = 10, -- In minutes, so every 10 minutes.

    -- Crashes or luck
    ChanceOfCrashOrLuck = 2, -- This is in % (1-100)
    Crash = { 20, 80 },      -- Min / Max
    Luck = { 20, 45 },       -- Min / Max

    -- If not not Chance of crash or luck, then this shit
    ChanceOfDown = 30,      -- If out of 100 hits less or equal to
    ChanceOfUp = 60,        -- If out of 100 is greater or equal to
    CasualDown = { 1, 10 }, -- Min / Max (If it goes down)
    CasualUp = { 1, 10 },   -- Min / Max (If it goes up)
}

Config.Ticker = {
    Enabled = true, -- Decide whether the real life price ticker should be enabled or not :)
    -- API (https://hermes.pyth.network/v2/updates/price/latest?ids[]=<price_feed_id>)
    -- Price Feed Ids: https://pyth.network/developers/price-feed-ids
    -- e.g. BTC/USD: e62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43
    -- e.g. ETH/USD: ffc2da2c0683a044aa167d4b420f18820c8413e1577f3a8af44e4d9492169b76
    PriceFeedId = "e62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43", -- BTC/USD
    tick_time = 2,                                                                    --- Minutes (Minimum is 2 minutes)
}

Config.Coinbase = {
    ProjectId = 'cbc9bde6-0bf5-4825-b3e7-2ea495657094',        -- Replace with your actual project ID from the Coinbase Cloud dashboard
    Network = 'base-sepolia',                                  -- e.g., 'base-mainnet', 'base-sepolia'
    TokenContractAddress = 'YOUR_ERC20_TOKEN_CONTRACT_ADDRESS' -- The address of the ERC-20 token contract
}
