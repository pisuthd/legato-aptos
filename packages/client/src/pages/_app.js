
import '@/styles/globals.css'

import "@aptos-labs/wallet-adapter-ant-design/dist/index.css";

import { MartianWallet } from "@martianwallet/aptos-wallet-adapter"
import { AptosWalletAdapterProvider } from '@aptos-labs/wallet-adapter-react'

const wallets = [new MartianWallet()];

export default function App({ Component, pageProps }) {
  return (
    <AptosWalletAdapterProvider plugins={wallets} autoConnect={true}>
      <Component {...pageProps} />
    </AptosWalletAdapterProvider>
  )
}
