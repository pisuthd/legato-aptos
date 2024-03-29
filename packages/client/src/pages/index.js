
 
// import Stake from "../components/Stake"

import MainLayout from '@/layouts/mainLayout';
import Panel from '@/components/Panel';

export default function Home(props) {

  return (
    <MainLayout bodyClassname="my-auto"> 
      <Panel/>
    </MainLayout>
  )
}

// export async function getStaticProps() {

//   const { fetchSuiSystem, getSuiPrice, fetchAllVault } = useSui()

//   const suiPrice = await getSuiPrice()

//   const { summary, avgApy, validators } = await fetchSuiSystem()

//   const vaults = await fetchAllVault("mainnet", summary, suiPrice)

//   return {
//     props: {
//       summary,
//       validators,
//       avgApy,
//       suiPrice,
//       vaults
//     },
//     revalidate: 600
//   };
// }