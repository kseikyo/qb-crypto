-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local coin = Config.Crypto.Coin
local bannedCharacters = { '%', '$', ';' }

-- Function
local function RefreshCrypto()
    local result = MySQL.query.await('SELECT * FROM crypto WHERE crypto = ?', { coin })
    if result and result[1] then
        Config.Crypto.Worth[coin] = result[1].worth
        if result[1].history then
            Config.Crypto.History[coin] = json.decode(result[1].history)
            TriggerClientEvent('qb-crypto:client:UpdateCryptoWorth', -1, coin, result[1].worth,
                json.decode(result[1].history))
        else
            TriggerClientEvent('qb-crypto:client:UpdateCryptoWorth', -1, coin, result[1].worth, nil)
        end
    end
end

local function GetTickerPrice()
    local promise = promise.new()
    local url = "https://hermes.pyth.network/v2/updates/price/latest?ids[]=" ..
    Config.Ticker.PriceFeedId .. "&parsed=true"
    PerformHttpRequest(url, function(err, result, headers)
        if err == 200 then
            local data = json.decode(result)
            if data and data.parsed and data.parsed[1] and data.parsed[1].price then
                local priceData = data.parsed[1].price
                local price = tonumber(priceData.price)
                local expo = tonumber(priceData.expo)
                if price and expo then
                    local finalPrice = price * (10 ^ expo)
                    promise:resolve({ price = finalPrice })
                else
                    promise:resolve({ error = "Invalid price or exponent in Hermes API response" })
                end
            else
                promise:resolve({ error = "Malformed response from Hermes API" })
            end
        else
            promise:resolve({ error = "Failed to fetch price from Hermes API. Status: " .. err })
        end
    end, 'GET')

    local result = Citizen.Await(promise)
    if result.price then
        return result.price
    else
        return result.error
    end
end

local function HandlePriceChance()
    local currentValue = Config.Crypto.Worth[coin]
    local prevValue = Config.Crypto.Worth[coin]
    local trend = math.random(0, 100)
    local event = math.random(0, 100)
    local chance = event - Config.Crypto.ChanceOfCrashOrLuck

    if event > chance then
        if trend <= Config.Crypto.ChanceOfDown then
            currentValue = currentValue - math.random(Config.Crypto.CasualDown[1], Config.Crypto.CasualDown[2])
        elseif trend >= Config.Crypto.ChanceOfUp then
            currentValue = currentValue + math.random(Config.Crypto.CasualUp[1], Config.Crypto.CasualUp[2])
        end
    else
        if math.random(0, 1) == 1 then
            currentValue = currentValue + math.random(Config.Crypto.Luck[1], Config.Crypto.Luck[2])
        else
            currentValue = currentValue - math.random(Config.Crypto.Crash[1], Config.Crypto.Crash[2])
        end
    end

    if currentValue <= Config.Crypto.Lower then
        currentValue = Config.Crypto.Lower
    elseif currentValue >= Config.Crypto.Upper then
        currentValue = Config.Crypto.Upper
    end

    if Config.Crypto.History[coin][4] then
        -- Shift array index 1 to 3
        for k = 3, 1, -1 do
            Config.Crypto.History[coin][k] = Config.Crypto.History[coin][k + 1]
        end
        -- Assign array index 4 to the latest result
        Config.Crypto.History[coin][4] = { PreviousWorth = prevValue, NewWorth = currentValue }
    else
        Config.Crypto.History[coin][#Config.Crypto.History[coin] + 1] = { PreviousWorth = prevValue, NewWorth =
        currentValue }
    end

    Config.Crypto.Worth[coin] = currentValue

    local history = json.encode(Config.Crypto.History[coin])
    local props = {
        ['worth'] = currentValue,
        ['history'] = history,
        ['crypto'] = coin
    }
    MySQL.update(
        'UPDATE crypto set worth = :worth, history = :history where crypto = :crypto',
        props,
        function(affectedRows)
            if affectedRows < 1 then
                print('Crypto not found, inserting new record for ' .. coin)
                MySQL.insert('INSERT INTO crypto (crypto, worth, history) VALUES (:crypto, :worth, :history)', props)
            end
            RefreshCrypto()
        end
    )
end

-- Commands

QBCore.Commands.Add('setcryptoworth', 'Set crypto value',
    { { name = 'crypto', help = 'Name of the crypto currency' }, { name = 'Value', help = 'New value of the crypto currency' } },
    false, function(source, args)
    local src = source
    local crypto = tostring(args[1])

    if crypto ~= nil then
        if Config.Crypto.Worth[crypto] ~= nil then
            local NewWorth = math.ceil(tonumber(args[2]))

            if NewWorth ~= nil then
                local PercentageChange = math.ceil(((NewWorth - Config.Crypto.Worth[crypto]) / Config.Crypto.Worth[crypto]) *
                100)
                local ChangeLabel = '+'

                if PercentageChange < 0 then
                    ChangeLabel = '-'
                    PercentageChange = (PercentageChange * -1)
                end

                if Config.Crypto.Worth[crypto] == 0 then
                    PercentageChange = 0
                    ChangeLabel = ''
                end

                Config.Crypto.History[crypto][#Config.Crypto.History[crypto] + 1] = {
                    PreviousWorth = Config.Crypto.Worth[crypto],
                    NewWorth = NewWorth
                }

                TriggerClientEvent('QBCore:Notify', src,
                    'You have changed the value of ' ..
                    Config.Crypto.Labels[crypto] ..
                    ' from: $' ..
                    Config.Crypto.Worth[crypto] ..
                    ' to: $' .. NewWorth .. ' (' .. ChangeLabel .. ' ' .. PercentageChange .. '%)')
                Config.Crypto.Worth[crypto] = NewWorth
                TriggerClientEvent('qb-crypto:client:UpdateCryptoWorth', -1, crypto, NewWorth)
                MySQL.insert(
                'INSERT INTO crypto (worth, history) VALUES (:worth, :history) ON DUPLICATE KEY UPDATE worth = :worth, history = :history',
                    {
                        ['worth'] = NewWorth,
                        ['history'] = json.encode(Config.Crypto.History[crypto]),
                    })
            else
                TriggerClientEvent('QBCore:Notify', src,
                    Lang:t('text.you_have_not_given_a_new_value', { crypto = Config.Crypto.Worth[crypto] }))
            end
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('text.this_crypto_does_not_exist'))
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('text.you_have_not_provided_crypto_available_qbit'))
    end
end, 'admin')

QBCore.Commands.Add('checkcryptoworth', '', {}, false, function(source)
    local src = source
    TriggerClientEvent('QBCore:Notify', src,
        Lang:t('text.the_qbit_has_a_value_of', { crypto = Config.Crypto.Worth['qbit'] }))
end)

QBCore.Commands.Add('crypto', '', {}, false, function(source)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local MyPocket = math.ceil(Player.PlayerData.money.crypto * Config.Crypto.Worth['qbit'])

    TriggerClientEvent('QBCore:Notify', src,
        Lang:t('text.you_have_with_a_value_of',
            { playerPlayerDataMoneyCrypto = Player.PlayerData.money.crypto, mypocket = MyPocket }))
end)

-- Events

RegisterServerEvent('qb-crypto:server:FetchWorth', function()
    for name, _ in pairs(Config.Crypto.Worth) do
        local result = MySQL.query.await('SELECT * FROM crypto WHERE crypto = ?', { name })
        if result[1] ~= nil then
            Config.Crypto.Worth[name] = result[1].worth
            if result[1].history ~= nil then
                Config.Crypto.History[name] = json.decode(result[1].history)
                TriggerClientEvent('qb-crypto:client:UpdateCryptoWorth', -1, name, result[1].worth,
                    json.decode(result[1].history))
            else
                TriggerClientEvent('qb-crypto:client:UpdateCryptoWorth', -1, name, result[1].worth, nil)
            end
        end
    end
end)

RegisterServerEvent('qb-crypto:server:ExchangeFail', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local ItemData = Player.Functions.GetItemByName('cryptostick')
    if ItemData ~= nil then
        exports['qb-inventory']:RemoveItem(src, 'cryptostick', 1, false, 'qb-crypto:server:ExchangeFail')
        TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items['cryptostick'], 'remove')
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.cryptostick_malfunctioned'), 'error')
    end
end)

RegisterServerEvent('qb-crypto:server:Rebooting', function(state, percentage)
    Config.Crypto.Exchange.RebootInfo.state = state
    Config.Crypto.Exchange.RebootInfo.percentage = percentage
end)

RegisterServerEvent('qb-crypto:server:GetRebootState', function()
    local src = source
    TriggerClientEvent('qb-crypto:client:GetRebootState', src, Config.Crypto.Exchange.RebootInfo)
end)

RegisterServerEvent('qb-crypto:server:SyncReboot', function()
    TriggerClientEvent('qb-crypto:client:SyncReboot', -1)
end)

RegisterServerEvent('qb-crypto:server:ExchangeSuccess', function(LuckChance)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local ItemData = Player.Functions.GetItemByName('cryptostick')
    if ItemData ~= nil then
        local LuckyNumber = math.random(1, 10)
        local DeelNumber = 1000000
        local Amount = (math.random(611111, 1599999) / DeelNumber)
        if LuckChance == LuckyNumber then
            Amount = (math.random(1599999, 2599999) / DeelNumber)
        end
        exports['qb-inventory']:RemoveItem(src, 'cryptostick', 1, false, 'qb-crypto:server:ExchangeSuccess')
        Player.Functions.AddMoney('crypto', Amount, 'qb-crypto:server:ExchangeSuccess')
        TriggerClientEvent('QBCore:Notify', src,
            Lang:t('success.you_have_exchanged_your_cryptostick_for', { amount = Amount }), 'success', 3500)
        TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items['cryptostick'], 'remove')
        TriggerClientEvent('qb-phone:client:AddTransaction', src, Player, {},
            Lang:t('credit.there_are_amount_credited', { amount = Amount }), 'Credit')
    end
end)

-- Callbacks

QBCore.Functions.CreateCallback('qb-crypto:server:HasSticky', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local Item = Player.Functions.GetItemByName('cryptostick')

    if Item ~= nil then
        cb(true)
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('qb-crypto:server:GetCryptoData', function(source, cb, name)
    local Player = QBCore.Functions.GetPlayer(source)
    local CryptoData = {
        History = Config.Crypto.History[name],
        Worth = Config.Crypto.Worth[name],
        Portfolio = Player.PlayerData.money.crypto,
        WalletId = Player.PlayerData.metadata['walletid'],
        WalletAddress = Player.PlayerData.metadata['wallet_address'] or nil,
        Coinbase = Config.Coinbase,
        TokenPrice = Config.Crypto.Worth['qbit'],
    }

    cb(CryptoData)
end)

QBCore.Functions.CreateCallback('qb-crypto:server:BuyCrypto', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)
    local total_price = math.floor(tonumber(data.Coins) * tonumber(Config.Crypto.Worth['qbit']))
    if Player.PlayerData.money.bank >= total_price then
        local CryptoData = {
            History = Config.Crypto.History['qbit'],
            Worth = Config.Crypto.Worth['qbit'],
            Portfolio = Player.PlayerData.money.crypto + tonumber(data.Coins),
            WalletId = Player.PlayerData.metadata['walletid'],
        }
        Player.Functions.RemoveMoney('bank', total_price, 'bought crypto')
        TriggerClientEvent('qb-phone:client:AddTransaction', source, Player, data,
            Lang:t('credit.you_have_qbit_purchased', { dataCoins = tonumber(data.Coins) }), 'Credit')
        Player.Functions.AddMoney('crypto', tonumber(data.Coins), 'bought crypto')
        cb(CryptoData)
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('qb-crypto:server:SellCrypto', function(source, cb, data)
    local Player = QBCore.Functions.GetPlayer(source)

    if Player.PlayerData.money.crypto >= tonumber(data.Coins) then
        local CryptoData = {
            History = Config.Crypto.History['qbit'],
            Worth = Config.Crypto.Worth['qbit'],
            Portfolio = Player.PlayerData.money.crypto - tonumber(data.Coins),
            WalletId = Player.PlayerData.metadata['walletid'],
        }
        Player.Functions.RemoveMoney('crypto', tonumber(data.Coins), 'sold crypto')
        local amount = math.floor(tonumber(data.Coins) * tonumber(Config.Crypto.Worth['qbit']))
        TriggerClientEvent('qb-phone:client:AddTransaction', source, Player, data,
            Lang:t('debit.you_have_sold', { dataCoins = tonumber(data.Coins) }), 'Debit')
        Player.Functions.AddMoney('bank', amount, 'sold crypto')
        cb(CryptoData)
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('qb-crypto:server:TransferCrypto', function(source, cb, data)
    local newCoin = tostring(data.Coins)
    local newWalletId = tostring(data.WalletId)
    for _, v in pairs(bannedCharacters) do
        newCoin = string.gsub(newCoin, '%' .. v, '')
        newWalletId = string.gsub(newWalletId, '%' .. v, '')
    end
    data.WalletId = newWalletId
    data.Coins = tonumber(newCoin)
    local Player = QBCore.Functions.GetPlayer(source)
    if Player.PlayerData.money.crypto < tonumber(data.Coins) then
        cb('notenough')
        return
    end

    -- Lookup recipient's on-chain wallet address. Prefer explicit metadata key 'wallet_address'.
    local recipientWallet = nil
    -- First try to find by walletid metadata (legacy flow)
    local queryByWalletId = '%"walletid":"' .. data.WalletId .. '"%'
    local res = MySQL.query.await('SELECT * FROM `players` WHERE `metadata` LIKE ?', { queryByWalletId })
    if res[1] ~= nil then
        local meta = json.decode(res[1].metadata or '{}')
        recipientWallet = meta['wallet_address'] or meta['walletid'] or nil
    end

    -- If not found, try to find by a dedicated wallet_address column (if present)
    if not recipientWallet then
        local res2 = MySQL.query.await('SELECT * FROM `players` WHERE `wallet_address` = ?', { data.WalletId })
        if res2[1] ~= nil then
            recipientWallet = res2[1].wallet_address
        end
    end

    if recipientWallet then
        -- Return the recipient on-chain address to the client so the SDK can initiate the transaction.
        cb({
            WalletAddress = recipientWallet,
            Coins = tonumber(data.Coins),
            Message = 'recipient_found'
        })
    else
        cb('notvalid')
    end
end)


-- Save a player's on-chain wallet address (called from client after sign-in via Coinbase SDK)
RegisterServerEvent('qb-crypto:server:SaveWalletAddress', function(address)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then return end
    local citizenid = xPlayer.PlayerData.citizenid

    -- Update metadata JSON if present
    local meta = xPlayer.PlayerData.metadata or {}
    meta['wallet_address'] = address
    xPlayer.PlayerData.metadata = meta

    -- Persist to DB; try to update metadata column and wallet_address column if available
    local updatedMeta = json.encode(meta)
    -- Update metadata
    MySQL.update('UPDATE players SET metadata = ? WHERE citizenid = ?', { updatedMeta, citizenid })
    -- Try to update wallet_address column if it exists (safe to run even if column missing)
    local ok, err = pcall(function()
        MySQL.update('UPDATE players SET wallet_address = ? WHERE citizenid = ?', { address, citizenid })
    end)
    if not ok then
        print('qb-crypto:server:SaveWalletAddress - wallet_address column not present or update failed: ' .. tostring(err))
    end

    TriggerClientEvent('QBCore:Notify', src, 'Wallet address saved')
end)


-- Client will call this event after broadcasting the on-chain tx: server can then reconcile in-game balances
RegisterServerEvent('qb-crypto:server:ConfirmOnchainTransfer', function(targetWallet, coins, txHash)
    local src = source
    local sender = QBCore.Functions.GetPlayer(src)
    if not sender then return end
    if sender.PlayerData.money.crypto < tonumber(coins) then
        TriggerClientEvent('QBCore:Notify', src, 'Not enough crypto to confirm transfer', 'error')
        return
    end

    -- Find recipient by wallet_address (metadata or dedicated column)
    local found = nil
    -- search metadata
    local query = '%"wallet_address":"' .. targetWallet .. '"%'
    local res = MySQL.query.await('SELECT * FROM `players` WHERE `metadata` LIKE ?', { query })
    if res[1] then found = res[1] end
    if not found then
        local res2 = MySQL.query.await('SELECT * FROM `players` WHERE wallet_address = ?', { targetWallet })
        if res2[1] then found = res2[1] end
    end

    -- Deduct from sender and credit recipient (if found). If recipient offline, update DB money field.
    sender.Functions.RemoveMoney('crypto', tonumber(coins), 'onchain transfer')
    if found then
        local Target = QBCore.Functions.GetPlayerByCitizenId(found.citizenid)
        if Target then
            Target.Functions.AddMoney('crypto', tonumber(coins), 'onchain transfer')
            TriggerClientEvent('qb-phone:client:AddTransaction', Target.PlayerData.source, Target, { Coins = coins }, 'There are ' .. coins .. " Qbit('s) credited!", 'Credit')
        else
            local MoneyData = json.decode(found.money)
            MoneyData.crypto = MoneyData.crypto + tonumber(coins)
            MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(MoneyData), found.citizenid })
        end
    end

    -- Optionally log the txHash to a table in future. For now, notify sender.
    TriggerClientEvent('QBCore:Notify', src, 'On-chain transfer confirmed' .. (txHash and (': '..txHash) or ''))
end)

-- Threads

CreateThread(function()
    while true do
        Wait(Config.Crypto.RefreshTimer * 60000)
        if not Config.Ticker.Enabled then
            HandlePriceChance()
        end
    end
end)

if Config.Ticker.Enabled then
    CreateThread(function()
        local Interval = Config.Ticker.tick_time * 60000
        if Config.Ticker.tick_time < 2 then
            Interval = 120000
        end
        while (true) do
            local get_coin_price = GetTickerPrice()
            if type(get_coin_price) == 'number' then
                Config.Crypto.Worth['qbit'] = get_coin_price
                MySQL.update('UPDATE crypto set worth = ? where crypto = ?', { get_coin_price, 'qbit' },
                    function(affectedRows)
                        if affectedRows > 0 then
                            RefreshCrypto()
                        end
                    end)
            else
                print('\27[31m' .. get_coin_price .. '\27[0m')
                Config.Ticker.Enabled = false
            end
            Wait(Interval)
        end
    end)
end
