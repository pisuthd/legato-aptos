import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";
import { useCallback } from "react";
import BigNumber from "bignumber.js"
import { useWallet } from "@aptos-labs/wallet-adapter-react";

const TYPE = "0x7bf8c83deaef80763a95c2727e36815cb66282024814df39c6170ee6f04bdd37::vault_maturity_dates::APR_2024"

const MODULE = "0x7bf8c83deaef80763a95c2727e36815cb66282024814df39c6170ee6f04bdd37"

const MATURITY_DATE = 1714483013

const RATE = 0.05

const useLegato = () => {

    const { account, signAndSubmitTransaction } = useWallet()

    const aptosConfig = new AptosConfig({ network: Network.TESTNET });
    const aptos = new Aptos(aptosConfig);

    const getBalanceAPT = useCallback(async (address) => {

        const resource = await aptos.getAccountResource({
            accountAddress: address,
            resourceType: "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>",
        });

        // Now we have access to the response type property
        const value = resource.coin.value;

        return Number((BigNumber(value)).dividedBy(BigNumber(10 ** 8)))
    }, [])

    const getBalancePT = useCallback(async (address) => {

        const resource = await aptos.getAccountResource({
            accountAddress: address,
            resourceType: "0x1::coin::CoinStore<0x7bf8c83deaef80763a95c2727e36815cb66282024814df39c6170ee6f04bdd37::vault::PT_TOKEN<0x7bf8c83deaef80763a95c2727e36815cb66282024814df39c6170ee6f04bdd37::vault_maturity_dates::APR_2024>>",
        });

        // Now we have access to the response type property
        const value = resource.coin.value;

        return Number((BigNumber(value)).dividedBy(BigNumber(10 ** 8)))
    }, [])

    const estimateOutput = (input) => {

        if (input === 0) {
            return 0
        }

        const currentDate = new Date().valueOf()
        const diffEpoch = (MATURITY_DATE - (currentDate / 1000).toFixed(0)) / 86400
        return input + (input * 0.05 * (diffEpoch / 365))
    }

    const onMint = useCallback(async (amount) => {

        if (!account) {
            return
        }

        const transaction = {
            data: {
                function: `${MODULE}::vault::mint`,
                typeArguments: [TYPE],
                functionArguments: [`${(BigNumber(amount)).multipliedBy(BigNumber(10 ** 8))}`]
            }
        }

        const response = await signAndSubmitTransaction(transaction);
        // wait for transaction
        await aptos.waitForTransaction({ transactionHash: response.hash });

    }, [account])

    return {
        onMint,
        estimateOutput,
        getBalancePT,
        getBalanceAPT
    }
}

export default useLegato