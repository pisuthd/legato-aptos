
import { ChevronUpDownIcon } from "@heroicons/react/20/solid"


const AmountInput = ({
    name,
    image,
    symbol,
    amount,
    onChange,
    currency, 
    disabled
}) => {
    return (
        <div className="flex h-[68px] relative bg-gray-700 rounded-lg p-2">
            <div className="absolute bottom-0 w-full text-2xl p-2 pl-0">
                <input disabled={disabled} id="large-input" name={name} value={amount} onChange={onChange} type="number" placeholder={"hello"} class="[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none block   px-2 py-2  bg-gray-700  border-transparent text-white focus:outline-none focus:border-transparent" />
            </div>
            <div className="absolute bottom-0 right-0 p-2 flex flex-row">
                
                <div className="bg-gray-600 flex flex-row font-medium py-3 px-2 rounded-md border-2 hover:cursor-pointer border-gray-700 ">
                    <div class="relative">
                        <img class="h-6 w-6 mx-1 rounded-full" src={image} alt="" /> 
                    </div>
                    <div className="px-2 text-center w-[90px]">
                        {symbol}
                    </div>
                    <div class="ml-auto ">
                        <ChevronUpDownIcon className="h-6 w-6 text-gray-300" />
                    </div>
                </div>
            </div>
        </div>
    )
}

export default AmountInput