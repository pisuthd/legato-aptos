import { useWallet } from "@aptos-labs/wallet-adapter-react";

import { useCallback, useEffect, useState } from "react"
import AmountInput from "./AmountInput"
import useLegato from "@/hooks/useLegato";
import Spinner from "./Spinner";

const Panel = () => {

    const { account } = useWallet()
    const { getBalanceAPT, estimateOutput, onMint, getBalancePT } = useLegato()

    const address = account && account.address

    const [tab, setTab] = useState(0)
    const [amount, setAmount] = useState(0)
    const [estimate, setEstimate] = useState(0)
    const [available, setAvailable] = useState(0)
    const [loading, setLoading] = useState(false)
    const [errorMessage, setErrorMessage] = useState()
    const [tick, setTick] = useState(1)

    const handleChange = (e) => {
        const value = Number(e.target.value)
        setAmount(value)
        setEstimate(estimateOutput(value))
    }

    useEffect(() => {
        address && tab === 0 && getBalanceAPT(address).then(setAvailable)
        address && tab === 1 && getBalancePT(address).then(setAvailable)
    }, [address, tab, tick])

    const onNext = useCallback(async () => {

        setErrorMessage()

        if (amount < 1) {
            setErrorMessage("Amount must be > 1")
            return
        }

        setLoading(true)

        try {
            await onMint(amount)
            setTick(tick + 1)
        } catch (e) {
            console.log(e)
            setErrorMessage(`${e.message}`)
        }

        setLoading(false)

    }, [onMint, amount, tick])


    return (
        <>
            <div class="wrapper p-2 mb-10">
                <div className=" mx-auto max-w-lg">
                    <h5 class="text-2xl text-center text-white font-bold  my-3  ">
                        Lock-in APT Staking
                    </h5>
                    <div class={` bg-gray-900 p-6 w-full border border-gray-700 rounded-2xl`}>

                        <div className='grid grid-cols-4 gap-2 text-xl'>

                            <div onClick={() => setTab(0)} class={`col-span-2 ${tab === 0 && "bg-gray-700"} flex gap-3 items-center border-2 border-gray-700  hover:border-blue-700 flex-1 p-2 px-4 mb-2 hover:cursor-pointer rounded-md`}>

                                <div className="mx-auto">
                                    <h3 class={`text-md font-medium text-white text-center`}>Deposit</h3>
                                </div>
                            </div>
                            <div onClick={() => setTab(1)} class={`col-span-2 ${tab === 1 && "bg-gray-700"} flex gap-3 items-center border-2 border-gray-700  hover:border-blue-700 flex-1 p-2 px-4 mb-2 hover:cursor-pointer rounded-md`}>

                                <div className="mx-auto">
                                    <h3 class={`text-md font-medium text-white  `}>Withdraw</h3>
                                </div>
                            </div>
                        </div>

                        <div className="mt-6">
                            <AmountInput
                                name="baseAmount"
                                image={`/aptos-apt-logo.svg`}
                                symbol={tab == 0 ? " APTOS " : "PT-APR24"}
                                amount={amount}
                                onChange={handleChange}
                            />
                            <div className="text-xs flex p-2 flex-row text-gray-300 border-gray-400  ">
                                <div className="font-medium ">
                                    Available: {Number(available).toFixed(3)}{` ${tab === 1 ? "PT-APR24" : "APT"}`}
                                </div>
                                <div className="ml-auto font-medium">
                                    Fixed APY: 5%
                                </div>
                            </div>
                        </div>

                        <div className="text-xs font-medium text-gray-300 text-center py-4 pt-1 max-w-sm mx-auto">
                            You will receive  {Number(estimate).toFixed(3)} PT which can be redeemed for APTOS in full after April 30, 2024
                        </div>

                        <button disabled={loading} onClick={onNext} className={`py-3 rounded-lg pl-10 pr-10 text-sm font-medium flex flex-row w-full justify-center bg-blue-700`}>
                            {loading && <Spinner />}
                            Next
                        </button>
                        {errorMessage && (
                            <div className="text-xs font-medium p-2 text-center text-yellow-300">
                                {errorMessage}
                            </div>
                        )}


                    </div>
                    <div className="max-w-lg ml-auto mr-auto">
                        <p class="text-neutral-400 text-sm p-5 text-center">
                            {`Legato on Aptos is still in development and available for access on the Aptos Testnet only`}
                        </p>
                    </div>
                </div>
            </div>

        </>
    )
}

export default Panel